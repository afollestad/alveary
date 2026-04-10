# Part 3c: GitHub and Worktrees

GitHub integration, GitHubCLIService, GitHubService, worktrees, branching, and PR discovery. Continues from Part 3b.

## Implementation Status

- [x] `GitHubCLIService`, `DefaultGitHubCLIService`, `GitHubService`, `CLIGitHubService`, `WorktreeManager`, `DefaultWorktreeManager`, `GitHubAssembly`, and the expanded `AppDI` wiring are implemented in the repo.
- [x] Focused regression coverage exists in `SkepTests/Services/GitHubCLIServiceTests.swift`, `SkepTests/Services/GitHubServiceTests.swift`, and `SkepTests/Services/WorktreeManagerTests.swift`.
- [ ] Manual validation gate remains: verify the GitHub device-flow UX end-to-end from the app shell, including URL parsing, explicit browser launch, cancel/retry behavior, and reconnect after an auth loss.

## GitHub Integration

GitHub operations use the **`gh` CLI** via Foundation `Process`.

### Operations via `gh` CLI

| Operation | Command |
|---|---|
| List PRs | `gh pr list --state open --json [fields]` |
| List issues | `gh issue list --state open --json [fields]` |
| Search issues | `gh issue list --search <query> --json [fields]` |
| PR/issue details | `gh pr view <number> --json [fields]` |
| PR checkout | `gh pr checkout <number> --branch <name> --force` |
| Auth status | `gh auth status` |
| API calls | `gh api <endpoint>` for GraphQL/REST |
| Logout | `gh auth logout --hostname github.com` |

### Authentication

Authentication is handled entirely via the `gh` CLI:

```
gh auth login --web --clipboard
```

Works without a TTY (validated). The process outputs two lines to stdout:
```
! One-time code (F9B7-1C75) copied to clipboard
Open this URL to continue in your web browser: https://github.com/login/device
```

`gh` copies the device code to the clipboard, then blocks until the browser flow completes. Exits 0 on success. No custom OAuth or token management needed -- `gh` handles its own credential store.

**Flow (validated end-to-end):**
1. `GitHubCLIService.authenticate()` spawns `gh auth login --web --clipboard` via `Process` with piped stdout.
2. Parses stdout for the one-time code (regex: `One-time code \(([A-Z0-9-]+)\)`). The verification URL is the stable GitHub device-login URL (`https://github.com/login/device`), so it can be supplied directly.
3. UI shows a modal with the device code and "Open browser" button. `--web` does NOT auto-open the browser without a TTY -- the app opens the fixed device-login URL via `NSWorkspace.shared.open(url)`.
4. Modal shows "Waiting for authorization..." while `awaitAuthentication()` blocks until `gh` exits 0.
5. On success, modal dismisses with a brief "Connected to GitHub" confirmation.
6. If a later `gh` command fails with "not authenticated", surface a reconnect CTA and let the user explicitly restart the device flow.

### GitHubCLIService

Dedicated service wrapping the `gh` CLI for auth and lifecycle:

```swift
/// Auth result with device code and URL for the browser flow.
struct GitHubDeviceCode: Sendable {  // Skep/Services/Git/GitHubCLIService.swift
    let code: String       // e.g. "F9B7-1C75"
    let verificationURL: URL  // https://github.com/login/device
}

@MainActor
protocol GitHubCLIService {  // Skep/Services/Git/GitHubCLIService.swift
    /// Returns `gh` version string, or nil if not installed.
    func checkInstalled() async -> String?

    /// Returns true if `gh` is authenticated.
    func isAuthenticated() async -> Bool

    /// Starts `gh auth login --web --clipboard`. Returns device code immediately;
    /// call `awaitAuthentication()` to block until the browser flow completes.
    func authenticate() async throws -> GitHubDeviceCode

    /// Blocks until auth process exits. Returns true on exit 0.
    func awaitAuthentication() async throws -> Bool

    /// Cancels in-progress auth by terminating the `gh` process.
    func cancelAuthentication()

    /// Runs a `gh` command and returns the result.
    func run(args: [String], in directory: String?) async throws -> ShellResult
}
```

**How the UI uses this:**

```swift
let deviceCode = try await gitHubCLIService.authenticate()
showAuthModal(code: deviceCode.code, url: deviceCode.verificationURL)
// User taps "Open browser" → NSWorkspace.shared.open(url)

let success = try await gitHubCLIService.awaitAuthentication()
if success {
    dismissAuthModal()
}

// On modal dismiss without completing auth:
gitHubCLIService.cancelAuthentication()
```

**Auth modal:**

```
┌─ Connect GitHub ─────────────────── ✕ ─┐
│                                        │
│  GitHub authentication code             │
│  copied to your clipboard.              │
│                                        │
│         F9B7-1C75                       │
│                                        │
│  Paste this code when prompted          │
│  in the browser.                        │
│                                        │
│            [ Open browser ]             │
│                                        │
│  ○ Waiting for authorization...         │
│                                        │
└────────────────────────────────────────┘
```

Shows the device code prominently (in case clipboard was overwritten), an "Open browser" button, and a spinner until `awaitAuthentication()` returns.

### Concrete Implementation

```swift
/// @MainActor to protect mutable `authProcess`; pipe reads use detached tasks.
@MainActor
class DefaultGitHubCLIService: GitHubCLIService {  // Skep/Services/Git/DefaultGitHubCLIService.swift
    private let shell: ShellRunner
    private var authProcess: Process?

    init(shell: ShellRunner) {
        self.shell = shell
    }

    func checkInstalled() async -> String? {
        let result = try? await shell.run(
            executable: "/usr/bin/which", args: ["gh"], timeout: .seconds(2)
        )
        guard let path = result?.stdout.trimmingCharacters(in: .whitespacesAndNewlines),
              result?.succeeded == true, !path.isEmpty else { return nil }
        let version = try? await shell.run(executable: path, args: ["--version"], timeout: .seconds(3))
        return version?.succeeded == true
            ? version?.stdout.trimmingCharacters(in: .whitespacesAndNewlines) : nil
    }

    func isAuthenticated() async -> Bool {
        let result = try? await shell.run(
            executable: "/usr/bin/env", args: ["gh", "auth", "status"], timeout: .seconds(5)
        )
        return result?.succeeded ?? false
    }

    func authenticate() async throws -> GitHubDeviceCode {
        // Kill any stale auth process.
        cancelAuthentication()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["gh", "auth", "login", "--web", "--clipboard"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        authProcess = process

        // Detached task: `gh` writes the code then blocks for browser flow.
        let handle = stdout.fileHandleForReading
        nonisolated(unsafe) let unsafeHandle = handle
        let codePattern = /One-time code \(([A-Z0-9-]+)\)/
        let code: String? = try await Task.detached {
            for try await line in unsafeHandle.bytes.lines {
                if let match = line.firstMatch(of: codePattern) {
                    return String(match.1)
                }
            }
            return nil
        }.value

        guard let code else {
            process.terminate()
            authProcess = nil
            throw GitHubError.authParseFailed
        }
        guard let url = URL(string: "https://github.com/login/device") else {
            authProcess = nil
            throw GitHubError.authParseFailed
        }

        return GitHubDeviceCode(code: code, verificationURL: url)
    }

    /// Blocks until auth exits. 5-minute timeout; returns false on timeout.
    func awaitAuthentication() async throws -> Bool {
        guard let process = authProcess else { return false }
        let result = await withCheckedContinuation { continuation in
            let resumed = OSAllocatedUnfairLock(initialState: false)
            process.terminationHandler = { proc in
                if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                    continuation.resume(returning: proc.terminationStatus == 0)
                }
            }
            // If process already exited before handler was set, resume immediately.
            if !process.isRunning {
                if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                    continuation.resume(returning: process.terminationStatus == 0)
                }
            }
            // 5-minute timeout to avoid blocking forever.
            Task {
                try? await Task.sleep(for: .seconds(300))
                if resumed.withLock({ let old = $0; $0 = true; return !old }) {
                    process.terminate()
                    continuation.resume(returning: false)
                }
            }
        }
        authProcess = nil
        return result
    }

    func cancelAuthentication() {
        guard let process = authProcess else { return }
        if process.isRunning { process.terminate() }
        authProcess = nil
    }

    func run(args: [String], in directory: String?) async throws -> ShellResult {
        try await shell.run(executable: "/usr/bin/env", args: ["gh"] + args, in: directory)
    }
}

enum GitHubError: Error, Sendable {  // Skep/Services/Git/GitHubCLIService.swift
    case authParseFailed
}
```

`GitHubService` delegates to `GitHubCLIService` for `gh` calls, keeping auth/lifecycle isolated from PR/issue logic.

V1 does not create PRs directly from app UI. When the user taps **Open PR** in the diff viewer, the app sends that request to the agent, and the agent can invoke `gh pr create` inside the worktree. The app-side `GitHubService` is therefore limited to discovery, CI inspection, and checkout flows.

**Unit tests for GitHubCLIService** (inject `MockShellRunner`): cover all public methods with standard happy-path and error tests. Non-obvious:
- `authenticate()` kills a stale auth process from a previous incomplete flow before starting a new one
- `awaitAuthentication()` returns false after 5-minute timeout and terminates the process

### CLI Detection

Check `gh` installation at startup via `checkInstalled()`. If missing, disable GitHub features with install guidance (`brew install gh`). Same pattern for agent CLIs (`claude --version`, `codex --version`).

### CI / Check Run Status

Fetched via `statusCheckRollup` in `gh pr list`. Contains `CheckRun` and `StatusContext` entries. Aggregate status: `pass` (all success), `fail` (any failure), `pending` (any pending), `none` (empty).

### Implementation

Injectable `GitHubService` protocol for PR/issue read operations:

```swift
enum CIStatus: Sendable { case pass, fail, pending, none }  // Skep/Services/Git/GitHubService.swift

protocol GitHubService {  // Skep/Services/Git/GitHubService.swift
    func listPRs(in directory: String) async throws -> [PRInfo]
    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus
    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws
}

struct PRInfo: Identifiable, Sendable {  // Skep/Services/Git/GitHubService.swift
    var id: Int { number }
    let number: Int
    let title: String
    let url: String
    let state: String
    let headRefName: String
    let ciStatus: CIStatus
}
```

### Concrete Implementation

```swift
class CLIGitHubService: GitHubService {  // Skep/Services/Git/CLIGitHubService.swift
    private let ghCLI: GitHubCLIService

    init(ghCLI: GitHubCLIService) {
        self.ghCLI = ghCLI
    }

    func listPRs(in directory: String) async throws -> [PRInfo] {
        let result = try await ghCLI.run(
            args: ["pr", "list", "--state", "open", "--json",
                   "number,title,url,state,headRefName,statusCheckRollup"],
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        guard let data = result.stdout.data(using: .utf8),
              let items = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]]
        else { return [] }

        return items.compactMap { item in
            guard let number = item["number"] as? Int,
                  let title = item["title"] as? String,
                  let url = item["url"] as? String,
                  let state = item["state"] as? String,
                  let headRefName = item["headRefName"] as? String
            else { return nil }
            let checks = item["statusCheckRollup"] as? [[String: Any]] ?? []
            return PRInfo(
                number: number, title: title, url: url,
                state: state, headRefName: headRefName,
                ciStatus: aggregateCIStatus(checks)
            )
        }
    }

    func checkRunStatus(prNumber: Int, in directory: String) async throws -> CIStatus {
        let result = try await ghCLI.run(
            args: ["pr", "view", "\(prNumber)", "--json", "statusCheckRollup"],
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        guard let data = result.stdout.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let checks = json["statusCheckRollup"] as? [[String: Any]]
        else { return .none }
        return aggregateCIStatus(checks)
    }

    func checkoutPRBranch(prNumber: Int, branchName: String, in directory: String) async throws {
        let result = try await ghCLI.run(
            args: ["pr", "checkout", "\(prNumber)", "--branch", branchName, "--force"],
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
    }

    /// Aggregates `CheckRun` and `StatusContext` entries into a single CI status.
    private func aggregateCIStatus(_ checks: [[String: Any]]) -> CIStatus {
        guard !checks.isEmpty else { return .none }
        var hasPending = false
        for check in checks {
            let typeName = check["__typename"] as? String
            if typeName == "StatusContext" {
                let state = check["state"] as? String  // SUCCESS | FAILURE | ERROR | EXPECTED | PENDING
                if state == "FAILURE" || state == "ERROR" { return .fail }
                if state == "PENDING" || state == "EXPECTED" { hasPending = true }
            } else {
                let conclusion = check["conclusion"] as? String  // CheckRun: status + conclusion
                let status = check["status"] as? String
                if conclusion == "FAILURE" || conclusion == "ERROR" { return .fail }
                let isRunning = status == "IN_PROGRESS" || status == "QUEUED"
                let noConclusion = conclusion == nil || conclusion?.isEmpty == true
                if isRunning || noConclusion { hasPending = true }
            }
        }
        return hasPending ? .pending : .pass
    }
}
```

**Unit tests for GitHubService** (inject `MockGitHubCLIService`): cover all public methods with standard happy-path and error tests. Non-obvious:
- `checkRunStatus()` correctly distinguishes `CheckRun` (status/conclusion) vs `StatusContext` (state) entries and handles empty-string conclusion as pending

---

## Git Worktrees

Each thread gets an isolated working copy via git worktrees, so agents don't affect the main branch.

### Worktree Creation

```
createWorktree(projectPath, taskName, projectId, baseRef?, remoteName?)
  → Resolve base ref (prefer <remoteName>/<baseRef> after fetch, otherwise local <baseRef> or HEAD)
  → Pick a unique worktree/branch target (slug-hash + optional -2/-3 suffix)
  → git worktree add --no-track -b <branch> <path> <resolvedBase>
  → Preserve .env files from source to worktree
  → Run setup script with injected SKEP_* env vars
  → git push --set-upstream <remoteName> <branch> (if pushOnCreate enabled and a remote was chosen)
  → Return WorktreeInfo
```

**Branch naming**: `{prefix}/{slugified-thread-name}-{3-char-hash}` with an optional numeric collision suffix (`-2`, `-3`, ...) when an existing branch/worktree already uses that base name. Prefix comes from `AppSettings.branchPrefix` (default: `skep`), slug is lowercased with non-alphanumerics replaced by hyphens, and hash is 3 hex chars from SHA-256.

Examples:
- Thread "Fix auth bug" with prefix `skep` → branch `skep/fix-auth-bug-a2b`
- Thread "Add unit tests for CartView" with prefix `af` → branch `af/add-unit-tests-for-cartview-c7f`

**Worktree path**: `{projectPath}/../worktrees/{project-slug}-{project-path-hash}/{slugified-name}-{hash}/` with the same optional numeric collision suffix as the branch target. The project namespace is derived from the canonical project path, not just the last path component, so two sibling clones named `my-app` cannot collide under the shared `../worktrees/` parent.

Example: project at `/Users/you/Development/my-app`, thread "Fix auth bug" → worktree at `/Users/you/Development/worktrees/my-app-9c4f21/fix-auth-bug-a2b/`

**Features**: preserves gitignored files (`.env`, etc.) from source to worktree; `--no-track` to avoid auto-tracking base ref; `--set-upstream` push after creation if remote exists.

### Worktree from Existing Branch

```
createWorktreeFromBranch(projectPath, threadName, branchName, remoteName?)
  → git fetch <remoteName> <branchName> (best effort, only when a preferred remote exists)
  → Pick a unique worktree path for this thread name
  → git worktree add <path> <branchName>
  → Preserve gitignored files
  → Run setup script with injected SKEP_* env vars
```

PR checkout remains a separate concern: use `GitHubService.checkoutPRBranch(...)` to materialize the PR's local branch first, then call `createFromBranch(projectPath:threadName:branch:remoteName:)` with that branch name and the project's persisted `remoteName`.

### Worktree Cleanup

```
removeWorktree(projectPath, worktreePath, branch?)
  → Safety: verify NOT the main repository
  → Safety: verify via git worktree list --porcelain
  → Run teardown script (best effort)
  → git worktree remove --force <path>
  → If fails: chmod +w, retry
  → Delete branch reference
```

**Safety**: validate path is a worktree (not the main repo) via `git worktree list --porcelain` before deletion.

### Lifecycle Scripts (Setup and Teardown)

Configured in project-level config. `scripts.setup` runs after worktree creation (blocking), `scripts.teardown` runs before destruction. Both run in the worktree directory with injected `SKEP_THREAD_NAME`, `SKEP_PROJECT_PATH`, `SKEP_WORKTREE_PATH`, `SKEP_BRANCH_NAME`, and `SKEP_PORT_SEED` variables. `SKEP_PORT_SEED` should be derived from the final unique worktree/branch target so colliding thread titles do not accidentally claim the same development port. During teardown, `SKEP_THREAD_NAME` may fall back to the worktree directory name because cleanup only has worktree metadata available.

**Timeout and cancellation**: setup scripts use `ShellRunner.run(timeout:)` with configurable timeout (default 5 min). Exceeding timeout terminates the process and fails thread creation. Adjustable via `scripts.setupTimeoutSeconds` in `.skep.json`. If the owning async task is canceled (for example by shutdown or a future explicit cancel UI), `ShellRunner` must reap the child process instead of leaving the setup script orphaned.

### Listing Worktrees

Use `git worktree list --porcelain` to enumerate worktrees. Parse for `worktree <path>`, `HEAD <sha>`, `branch refs/heads/<name>` lines. Fetched on-demand, not persisted.

### Tracking Worktrees

The database stores `branch` and `worktreePath` on each thread. The worktree list is fetched from Git on-demand -- not cached in the DB.

### Implementation

Injectable `WorktreeManager` protocol:

Phase 3 already introduced a minimal placeholder `WorktreeManager` surface so `ConversationViewModel.setupAndStart()` could compile before the Git layer existed. Expand that same protocol here rather than replacing it: preserve the Phase 3 `create(projectPath:threadName:baseRef:remoteName:)` and `remove(projectPath:worktreePath:branch:)` entry points, then add the extra Git-worktree-only APIs (`createFromBranch(..., remoteName:)`, `deleteBranch`, `list`) plus the real `DefaultWorktreeManager` implementation.

```swift
struct WorktreeInfo: Identifiable, Sendable {  // Skep/Services/Git/WorktreeManager.swift
    var id: String { path }
    let path: String           // Absolute path to the worktree directory
    let branch: String         // Branch checked out in this worktree
}

protocol WorktreeManager {  // Skep/Services/Git/WorktreeManager.swift
    func create(projectPath: String, threadName: String, baseRef: String?, remoteName: String?) async throws -> WorktreeInfo
    func createFromBranch(projectPath: String, threadName: String, branch: String, remoteName: String?) async throws -> WorktreeInfo
    func remove(projectPath: String, worktreePath: String, branch: String?) async throws
    func deleteBranch(projectPath: String, branch: String) async throws
    func list(projectPath: String) async throws -> [WorktreeInfo]

}
```

### Concrete Implementation

`DefaultWorktreeManager` should be a singleton `actor`, not a plain class. Worktree operations are infrequent and user-driven, so v1 can afford global serialization here. That serialization closes the race where two concurrent `create()` / `createFromBranch()` calls with the same thread name could otherwise both observe the same "free" target before either `git worktree add` runs, or a create/remove pair could interleave against the same path.

```swift
actor DefaultWorktreeManager: WorktreeManager {  // Skep/Services/Git/DefaultWorktreeManager.swift
    private let settingsService: SettingsService
    private let shell: ShellRunner

    private struct WorktreeTarget {
        let path: String
        let branch: String
    }

    init(settingsService: SettingsService, shell: ShellRunner) {
        self.settingsService = settingsService
        self.shell = shell
    }

    func create(projectPath: String, threadName: String, baseRef: String?, remoteName: String?) async throws -> WorktreeInfo {
        let settings = await settingsService.current
        let target = try await resolveWorktreeTarget(
            projectPath: projectPath,
            threadName: threadName,
            branchPrefix: settings.branchPrefix
        )
        let resolvedBase = await resolveBaseRef(projectPath: projectPath, baseRef: baseRef, remoteName: remoteName)

        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "add", "--no-track", "-b", target.branch, target.path, resolvedBase],
            in: projectPath
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }

        try await postCreateSetup(
            projectPath: projectPath,
            worktreePath: target.path,
            threadName: threadName,
            branch: target.branch,
            rollbackBranch: target.branch
        )

        if settings.pushOnCreate, let remoteName {
            _ = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["push", "--set-upstream", remoteName, target.branch],
                in: target.path
            )
        }

        return WorktreeInfo(path: target.path, branch: target.branch)
    }

    func remove(projectPath: String, worktreePath: String, branch: String?) async throws {
        // Verify this is a worktree, not the main repo
        let listResult = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "list", "--porcelain"],
            in: projectPath
        )
        guard listResult.succeeded else { throw GitError.commandFailed(listResult.stderr) }
        // Canonicalize paths for reliable comparison (slashes, symlinks, `.`/`..`).
        let canonicalProject = URL(fileURLWithPath: projectPath).standardizedFileURL.resolvingSymlinksInPath().path
        let canonicalWorktree = URL(fileURLWithPath: worktreePath).standardizedFileURL.resolvingSymlinksInPath().path
        let worktrees = parseWorktreeList(listResult.stdout)
        let isWorktree = worktrees.contains {
            URL(fileURLWithPath: $0.path).standardizedFileURL.resolvingSymlinksInPath().path == canonicalWorktree
        }
        let isMainRepo = canonicalProject == canonicalWorktree
        guard isWorktree && !isMainRepo else {
            throw GitError.commandFailed("Refusing to remove: \(worktreePath) is not a worktree")
        }

        // Best-effort teardown script.
        let config = SkepProjectConfig(projectPath: projectPath)
        if let script = config.teardownScript {
            _ = try? await shell.run(
                executable: "/bin/sh", args: ["-c", script],
                in: worktreePath,
                environment: buildLifecycleScriptEnvironment(
                    projectPath: projectPath,
                    worktreePath: worktreePath,
                    threadName: URL(fileURLWithPath: worktreePath).lastPathComponent,
                    branch: branch
                ),
                timeout: .seconds(60)
            )
        }

        var result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "remove", "--force", worktreePath],
            in: projectPath
        )
        // Retry with chmod +w on permission error (e.g. node_modules)
        if !result.succeeded && result.stderr.contains("permission") {
            _ = try? await shell.run(
                executable: "/bin/chmod", args: ["-R", "+w", worktreePath]
            )
            result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["worktree", "remove", "--force", worktreePath],
                in: projectPath
            )
        }
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }

        // Force-delete branch (may have unmerged work). Ignore only the already-missing
        // branch case; any real deletion failure should abort the thread delete so the
        // SwiftData record remains available for retry.
        if let branch {
            try await deleteBranch(projectPath: projectPath, branch: branch)
        }
    }

    func deleteBranch(projectPath: String, branch: String) async throws {
        let branchExists = (try? await shell.run(
            executable: "/usr/bin/git",
            args: ["show-ref", "--verify", "--quiet", "refs/heads/\(branch)"],
            in: projectPath
        ))?.succeeded == true
        guard branchExists else { return }
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["branch", "-D", branch],
            in: projectPath
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
    }

    func createFromBranch(projectPath: String, threadName: String, branch: String, remoteName: String?) async throws -> WorktreeInfo {
        let settings = await settingsService.current
        let target = try await resolveWorktreeTarget(
            projectPath: projectPath,
            threadName: threadName,
            branchPrefix: settings.branchPrefix
        )

        if let remoteName {
            _ = try? await shell.run(
                executable: "/usr/bin/git",
                args: ["fetch", remoteName, branch],
                in: projectPath,
                timeout: .seconds(30)
            )
        }

        // Check out existing branch (no new branch created)
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "add", target.path, branch],
            in: projectPath
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }

        try await postCreateSetup(
            projectPath: projectPath,
            worktreePath: target.path,
            threadName: threadName,
            branch: branch,
            rollbackBranch: nil
        )

        return WorktreeInfo(path: target.path, branch: branch)
    }

    func list(projectPath: String) async throws -> [WorktreeInfo] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["worktree", "list", "--porcelain"],
            in: projectPath
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        return parseWorktreeList(result.stdout)
    }

    // MARK: - Worktree Setup Helpers

    private func resolveBaseRef(projectPath: String, baseRef: String?, remoteName: String?) async -> String {
        let requestedBase = baseRef ?? "HEAD"
        guard requestedBase != "HEAD" else { return "HEAD" }
        if let remoteName {
            let fetchSucceeded = (try? await shell.run(
                executable: "/usr/bin/git",
                args: ["fetch", remoteName, requestedBase],
                in: projectPath,
                timeout: .seconds(30)
            ))?.succeeded == true
            if fetchSucceeded {
                return "\(remoteName)/\(requestedBase)"
            }
        }
        return requestedBase
    }

    /// Returns a unique path/branch target for worktree creation. Repeated identical
    /// thread names keep the same readable slug/hash base and add `-2`, `-3`, ... only
    /// when the filesystem or local refs already claim the unsuffixed candidate.
    private func resolveWorktreeTarget(
        projectPath: String,
        threadName: String,
        branchPrefix: String
    ) async throws -> WorktreeTarget {
        let slug = slugify(threadName)
        let hash = shortHash(threadName)
        let worktreesDir = URL(fileURLWithPath: projectPath)
            .deletingLastPathComponent()
            .appendingPathComponent("worktrees")
            .appendingPathComponent(projectNamespace(for: projectPath))
        let baseName = "\(slug)-\(hash)"
        for suffix in 0..<10_000 {
            let candidateName = suffix == 0 ? baseName : "\(baseName)-\(suffix + 1)"
            let candidatePath = worktreesDir.appendingPathComponent(candidateName).path
            let candidateBranch = "\(branchPrefix)/\(candidateName)"
            let branchExists = (try? await shell.run(
                executable: "/usr/bin/git",
                args: ["show-ref", "--verify", "--quiet", "refs/heads/\(candidateBranch)"],
                in: projectPath
            ))?.succeeded == true
            if !FileManager.default.fileExists(atPath: candidatePath) && !branchExists {
                return WorktreeTarget(path: candidatePath, branch: candidateBranch)
            }
        }
        throw GitError.commandFailed("Unable to find a unique worktree target for \(threadName)")
    }

    /// Namespaces the shared `../worktrees` parent by canonical project path so sibling
    /// clones with the same folder name do not collide.
    private func projectNamespace(for projectPath: String) -> String {
        let canonicalPath = URL(fileURLWithPath: projectPath)
            .standardizedFileURL
            .resolvingSymlinksInPath()
            .path
        let slug = slugify(URL(fileURLWithPath: canonicalPath).lastPathComponent)
        let digest = SHA256.hash(data: Data(canonicalPath.utf8))
        let hash = digest.prefix(3).map { String(format: "%02x", $0) }.joined()
        return "\(slug)-\(hash)"
    }

    /// Preserves gitignored files and runs setup script. Rolls back the worktree and,
    /// when this method created a fresh branch, deletes that branch on failure too.
    private func postCreateSetup(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String,
        rollbackBranch: String?
    ) async throws {
        let config = SkepProjectConfig(projectPath: projectPath)
        try preserveFiles(from: projectPath, to: worktreePath, patterns: config.preservePatterns)

        if let script = config.setupScript {
            let setupResult = try? await shell.run(
                executable: "/bin/sh", args: ["-c", script],
                in: worktreePath,
                environment: buildLifecycleScriptEnvironment(
                    projectPath: projectPath,
                    worktreePath: worktreePath,
                    threadName: threadName,
                    branch: branch
                ),
                timeout: .seconds(config.setupTimeoutSeconds ?? 300)
            )
            guard setupResult?.succeeded == true else {
                // Roll back on failure. Surface cleanup failure explicitly instead of
                // pretending the rollback succeeded — the caller needs the surviving
                // worktree path/branch if manual cleanup is required.
                var removeResult = try? await shell.run(
                    executable: "/usr/bin/git",
                    args: ["worktree", "remove", "--force", worktreePath],
                    in: projectPath
                )
                if removeResult?.succeeded != true,
                   removeResult?.stderr.contains("permission") == true {
                    _ = try? await shell.run(
                        executable: "/bin/chmod",
                        args: ["-R", "+w", worktreePath]
                    )
                    removeResult = try? await shell.run(
                        executable: "/usr/bin/git",
                        args: ["worktree", "remove", "--force", worktreePath],
                        in: projectPath
                    )
                }
                var rollbackBranchDeleteFailed = false
                if let rollbackBranch {
                    let deleteBranchResult = try? await shell.run(
                        executable: "/usr/bin/git",
                        args: ["branch", "-D", rollbackBranch],
                        in: projectPath
                    )
                    rollbackBranchDeleteFailed = deleteBranchResult?.succeeded == false
                }
                if removeResult?.succeeded != true || rollbackBranchDeleteFailed {
                    throw GitError.commandFailed(
                        "Setup script failed: \(setupResult?.stderr ?? "timed out"). Cleanup also failed for worktree \(worktreePath) or rollback branch \(rollbackBranch ?? branch)."
                    )
                }
                throw GitError.commandFailed(
                    "Setup script failed: \(setupResult?.stderr ?? "timed out")"
                )
            }
        }
    }

    private func buildLifecycleScriptEnvironment(
        projectPath: String,
        worktreePath: String,
        threadName: String,
        branch: String?
    ) -> [String: String] {
        var env: [String: String] = [
            "SKEP_THREAD_NAME": threadName,
            "SKEP_PROJECT_PATH": projectPath,
            "SKEP_WORKTREE_PATH": worktreePath,
            "SKEP_PORT_SEED": shortHash(branch ?? worktreePath)
        ]
        if let branch {
            env["SKEP_BRANCH_NAME"] = branch
        }
        return env
    }

    // MARK: - Helpers

    /// Lowercased, non-alphanum replaced with hyphens, max 50 chars. Falls back to "thread".
    private func slugify(_ name: String) -> String {
        let slug = name.lowercased()
            .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { return "thread" }
        return String(slug.prefix(50))
    }

    /// Stable 3-hex discriminator used in the human-readable base name before any
    /// numeric collision suffix is applied.
    private func shortHash(_ input: String) -> String {
        let digest = SHA256.hash(data: Data(input.utf8))
        return digest.prefix(2).map { String(format: "%02x", $0) }.joined().prefix(3).description
    }

    /// Copies gitignored files matching patterns to the worktree. Supports globs.
    private func preserveFiles(from source: String, to destination: String, patterns configPatterns: [String]?) throws {
        var patterns = configPatterns ?? [".env", ".env.local", ".env.development"]
        let sourceURL = URL(fileURLWithPath: source)
        let destURL = URL(fileURLWithPath: destination)
        for pattern in patterns {
            let fullPattern = sourceURL.appendingPathComponent(pattern).path
            var gt = glob_t()
            defer { globfree(&gt) }
            guard glob(fullPattern, 0, nil, &gt) == 0 else { continue }
            for i in 0..<Int(gt.gl_pathc) {
                guard let cPath = gt.gl_pathv[i], let matchPath = String(validatingCString: cPath) else { continue }
                let relativePath = String(matchPath.dropFirst(sourceURL.path.count + 1))
                let destPath = destURL.appendingPathComponent(relativePath)
                try? FileManager.default.createDirectory(
                    at: destPath.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try? FileManager.default.copyItem(
                    atPath: matchPath,
                    toPath: destPath.path
                )
            }
        }
    }

    /// Parses `git worktree list --porcelain` output.
    private func parseWorktreeList(_ output: String) -> [WorktreeInfo] {
        var results: [WorktreeInfo] = []
        var currentPath: String?
        var currentBranch: String?
        for line in output.components(separatedBy: "\n") {
            if line.hasPrefix("worktree ") {
                currentPath = String(line.dropFirst(9))
            } else if line.hasPrefix("branch refs/heads/") {
                currentBranch = String(line.dropFirst(18))
            } else if line.isEmpty {
                if let path = currentPath, let branch = currentBranch {
                    results.append(WorktreeInfo(path: path, branch: branch))
                }
                currentPath = nil
                currentBranch = nil
            }
        }
        // Last block if no trailing newline
        if let path = currentPath, let branch = currentBranch {
            results.append(WorktreeInfo(path: path, branch: branch))
        }
        return results
    }
}
```

Tests can mock `ShellRunner` to verify worktree orchestration logic without creating real repos.

**Unit tests for WorktreeManager** (inject `MockShellRunner`, `InMemorySettingsService`): cover all public methods with standard happy-path and error tests. Non-obvious:
- `create()` expands glob patterns in `preservePatterns` (e.g. `.env.*` matches `.env.local`) and creates intermediate directories for nested patterns (e.g. `config/*.json`)
- `create()` falls back to the current local branch when `<remoteName>/HEAD` is unavailable, and prefers `<remoteName>/<baseRef>` when the remote fetch succeeds
- `create()` skips fetch/push behavior cleanly for local-only repositories where `remoteName == nil`
- `create()` appends `-2`, `-3`, ... when an identical thread name would otherwise collide with an existing worktree path or branch ref
- `create()` namespaces the shared `../worktrees` parent by canonical project path so two sibling clones with the same folder name do not collide on disk
- concurrent same-name `create()` / `createFromBranch()` calls serialize through the actor so the later caller observes the first caller's claimed target and gets the suffixed `-2` / `-3` path+branch instead of racing into the same candidate
- `create()` uses default preserve patterns (`.env`, `.env.local`, `.env.development`) when `preservePatterns` is nil
- `create()` honors `scripts.setupTimeoutSeconds` when present, otherwise defaults to 300 seconds
- `create()` passes the documented `SKEP_*` lifecycle variables into setup scripts
- `create()` rolls back both the worktree and the newly-created branch when `scripts.setup` fails or times out
- `create()` surfaces rollback failure explicitly when `scripts.setup` fails and either forced worktree removal or rollback-branch deletion also fails, instead of losing the cleanup pointer
- `createFromBranch()` rolls back (removes worktree) when `scripts.setup` fails or times out
- `remove()` refuses to remove the main repo path even with trailing slash or symlink (path canonicalization)
- `remove()` surfaces a failing `git worktree list --porcelain` command directly instead of falling through to a misleading "not a worktree" error
- `remove()` verifies the path is an actual worktree via `git worktree list --porcelain` (not just substring match)
- `remove()` force-removes dirty worktrees (`git worktree remove --force`) so thread delete still works when the worktree has local modifications or untracked files
- `remove()` runs `scripts.teardown` before removal (best-effort, doesn't block on failure) and injects the documented `SKEP_*` lifecycle variables
- `remove()` retries with `chmod +w` when initial removal fails with permission error
- `list()` handles last block without trailing newline

**Unit tests for `slugify()`:** Non-obvious:
- All-emoji or all-special-character input returns `"thread"` fallback (not empty string)

---

## Branching, Committing, and PRs

Branch creation is handled by `WorktreeManager.create()` (see above). Local git state for staging, diffing, and branch comparison uses `GitService` (see [Part 3b](part3b-git.md)). PR discovery, CI inspection, and PR checkout use `GitHubService` (see above). Opening a new PR from the diff viewer is agent-mediated in [Part 3d](part3d-diff-viewer.md), not a direct app-side `gh pr create` flow.

---
