# Part 3b: Git Operations

GitService, CLIGitService, FileListManager. Continues from Part 3a.

## Git Operations

All Git operations are performed by shelling out to the `git` CLI via Foundation `Process`. No Git library is used.

### Operations

| Operation | Command |
|---|---|
| Status | `git status --porcelain=v2 -z` with `--no-optional-locks --no-ahead-behind` |
| Diff | `git diff --no-color --unified=2000` |
| Stage | `git add -A`, `git add --`, `git rm --cached` |
| Reset | `git reset HEAD --` |
| Log | `git log` with custom format |
| Branch | `git rev-parse --abbrev-ref HEAD`, `git merge-base`, `git rev-list <remote>/<base>..HEAD --count` with local `<base>..HEAD` fallback when no tracked remote ref exists |
| List Files | `git ls-files` |

### Performance Optimizations

- Parallel execution of independent git reads with Swift concurrency (`async let`) where helpful.
- Untracked file line counting capped at 100KB per file.
- Buffer limits: 5MB for selected diff preview content, 30MB for raw `git diff` output.

Rename-aware summaries in the diff viewer must come from real git diff output, not from counting `FileStatus` rows. An unstaged filesystem move appears as a deleted source row plus an untracked destination row, but after `git add -A` git collapses it into one staged rename that still counts as **1 file changed** and may report `0 insertions, 0 deletions`.

### Implementation

Shell out to `git` via `Process` (Foundation). The CLI is universally available, and there is no compelling reason to add a Git library here.

Git operations are encapsulated in an injectable `GitService` protocol, resolved via Knit:

```swift
struct FileStatus: Identifiable, Sendable {  // Skep/Services/Git/GitService.swift
    var id: String { path + (isStaged ? "-staged" : "") }
    let path: String
    /// Original path for rename/copy records from porcelain v2. Nil for ordinary entries.
    /// Preserved so the diff viewer can keep focus anchored across path changes,
    /// render staged rename rows as `old → new`, and target full rename reverts.
    let originalPath: String?
    let status: Status
    let isStaged: Bool

    enum Status: String, Sendable {
        case modified, added, deleted, renamed, copied, untracked, unmerged
    }
}

struct CommitInfo: Identifiable, Sendable {  // Skep/Services/Git/GitService.swift
    var id: String { hash }
    let hash: String
    let message: String
    let author: String
    let date: Date
}

enum DiffScope: Sendable {  // Skep/Services/Git/GitService.swift
    case staged
    case unstaged
}

enum GitError: Error, Sendable {  // Skep/Services/Git/GitService.swift
    case commandFailed(String)
    case notARepository
    case outputTooLarge(String)
}

/// All Git operations take an explicit `directory` parameter. The caller always resolves
/// this from the active thread's worktree path (or project root if worktrees are disabled).
protocol GitService {  // Skep/Services/Git/GitService.swift
    func status(in directory: String) async throws -> [FileStatus]
    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String
    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String
    func stage(paths: [String], in directory: String) async throws
    func unstage(paths: [String], in directory: String) async throws
    func discard(paths: [String], in directory: String) async throws
    func log(in directory: String, limit: Int) async throws -> [CommitInfo]
    func currentBranch(in directory: String) async throws -> String
    func listFiles(in directory: String) async throws -> [String]
    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int
}
```

### Concrete Implementation

```swift
class CLIGitService: GitService {  // Skep/Services/Git/CLIGitService.swift
    private let shell: ShellRunner

    init(shell: ShellRunner) {
        self.shell = shell
    }

    func status(in directory: String) async throws -> [FileStatus] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["--no-optional-locks", "status", "--porcelain=v2", "-z", "--no-ahead-behind"],
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        return parseStatus(result.stdout)
    }

    func diff(paths: [String], scope: DiffScope, in directory: String) async throws -> String {
        var args = ["diff", "--no-color", "--unified=2000"]
        if scope == .staged {
            args.append("--cached")
        }
        args += ["--"] + paths
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: args,
            in: directory,
            stdoutLimitBytes: 30 * 1024 * 1024,
            stderrLimitBytes: 512 * 1024
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        guard !result.stdoutWasTruncated else {
            throw GitError.outputTooLarge("Diff output exceeded 30MB")
        }
        return result.stdout
    }

    /// Synthetic all-added diff for untracked files (`git diff` returns empty).
    func syntheticAddedDiff(for path: String, in directory: String) async throws -> String {
        let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(path)
        let byteCount = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard byteCount <= 100_000 else {
            throw GitError.outputTooLarge("Untracked file is too large to preview (>100KB)")
        }
        let content = try String(contentsOf: fileURL)
        let lines = content.split(separator: "\n", omittingEmptySubsequences: false)
        let lineCount = max(lines.count, 1)
        let body = lines.map { "+\($0)" }.joined(separator: "\n")
        return """
        diff --git a/\(path) b/\(path)
        new file mode 100644
        --- /dev/null
        +++ b/\(path)
        @@ -0,0 +1,\(lineCount) @@
        \(body)
        """
    }

    func stage(paths: [String], in directory: String) async throws {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["add", "--"] + paths,
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
    }

    func unstage(paths: [String], in directory: String) async throws {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["reset", "HEAD", "--"] + paths,
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
    }

    func discard(paths: [String], in directory: String) async throws {
        let statuses = try await status(in: directory)
        let untracked = Set(statuses.filter { $0.status == .untracked }.map(\.path))
        let tracked = paths.filter { !untracked.contains($0) }

        if !tracked.isEmpty {
            let result = try await shell.run(
                executable: "/usr/bin/git",
                args: ["restore", "--source=HEAD", "--staged", "--worktree", "--"] + tracked,
                in: directory
            )
            guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        }

        for path in paths where untracked.contains(path) {
            let fileURL = URL(fileURLWithPath: directory).appendingPathComponent(path)
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    func log(in directory: String, limit: Int) async throws -> [CommitInfo] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["log", "--pretty=format:%H%n%s%n%an%n%aI", "-\(limit)"],
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        return parseLog(result.stdout)
    }

    func currentBranch(in directory: String) async throws -> String {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-parse", "--abbrev-ref", "HEAD"],
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        return result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listFiles(in directory: String) async throws -> [String] {
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["ls-files"],
            in: directory
        )
        guard result.succeeded else { throw GitError.commandFailed(result.stderr) }
        return result.stdout.split(separator: "\n").map(String.init)
    }

    func commitsAheadOfBase(baseBranch: String, remoteName: String?, in directory: String) async throws -> Int {
        let compareRef: String
        if let remoteName {
            let remoteRef = "refs/remotes/\(remoteName)/\(baseBranch)"
            let remoteExists = (try? await shell.run(
                executable: "/usr/bin/git",
                args: ["show-ref", "--verify", "--quiet", remoteRef],
                in: directory
            ))?.succeeded == true
            compareRef = remoteExists ? "\(remoteName)/\(baseBranch)" : baseBranch
        } else {
            compareRef = baseBranch
        }
        let result = try await shell.run(
            executable: "/usr/bin/git",
            args: ["rev-list", "\(compareRef)..HEAD", "--count"],
            in: directory
        )
        guard result.succeeded else { return 0 }
        return Int(result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
    }

    // MARK: - Parsing

    /// Parse `git status --porcelain=v2 -z` output.
    /// Ordinary tracked entries start with `1` (9 space-separated fields).
    /// Rename/copy entries start with `2` (10 fields) and are followed by a second
    /// NUL-separated entry containing the original path.
    private func parseStatus(_ output: String) -> [FileStatus] {
        guard !output.isEmpty else { return [] }
        var results: [FileStatus] = []
        let entries = output.split(separator: "\0", omittingEmptySubsequences: true)
        var i = 0
        while i < entries.count {
            let line = String(entries[i])
            if line.hasPrefix("1 ") {
                let parts = line.split(separator: " ", maxSplits: 8)
                guard parts.count >= 9 else { i += 1; continue }
                let xy = String(parts[1])
                let path = String(parts[8])
                guard let indexChar = xy.first, let worktreeChar = xy.last else { i += 1; continue }
                if indexChar != "." {
                    results.append(FileStatus(path: path, originalPath: nil, status: statusFrom(indexChar), isStaged: true))
                }
                if worktreeChar != "." {
                    results.append(FileStatus(path: path, originalPath: nil, status: statusFrom(worktreeChar), isStaged: false))
                }
            } else if line.hasPrefix("2 ") {
                let parts = line.split(separator: " ", maxSplits: 9)
                guard parts.count >= 10 else { i += 1; continue }
                let xy = String(parts[1])
                let path = String(parts[9])
                let originalPath = i + 1 < entries.count ? String(entries[i + 1]) : nil
                guard let indexChar = xy.first, let worktreeChar = xy.last else { i += 1; continue }
                if indexChar != "." {
                    results.append(FileStatus(path: path, originalPath: originalPath, status: statusFrom(indexChar), isStaged: true))
                }
                if worktreeChar != "." {
                    results.append(FileStatus(path: path, originalPath: originalPath, status: statusFrom(worktreeChar), isStaged: false))
                }
                i += 1
            } else if line.hasPrefix("u ") {
                let parts = line.split(separator: " ", maxSplits: 10)
                guard parts.count >= 11 else { i += 1; continue }
                let path = String(parts[10])
                results.append(FileStatus(path: path, originalPath: nil, status: .unmerged, isStaged: false))
            } else if line.hasPrefix("? ") {
                let path = String(line.dropFirst(2))
                results.append(FileStatus(path: path, originalPath: nil, status: .untracked, isStaged: false))
            }
            i += 1
        }
        return results
    }

    private func statusFrom(_ char: Character) -> FileStatus.Status {
        switch char {
        case "M": .modified
        case "A": .added
        case "D": .deleted
        case "R": .renamed
        case "C": .copied
        default: .modified
        }
    }

    private static let isoFormatter = ISO8601DateFormatter()

    private func parseLog(_ output: String) -> [CommitInfo] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        var commits: [CommitInfo] = []
        var i = 0
        while i + 3 < lines.count {
            let hash = lines[i]
            let message = lines[i + 1]
            let author = lines[i + 2]
            let dateStr = lines[i + 3]
            let date = Self.isoFormatter.date(from: dateStr) ?? Date()
            commits.append(CommitInfo(hash: hash, message: message, author: author, date: date))
            i += 4
        }
        return commits
    }
}
```

`ShellRunner` (`Skep/Services/Shell/ShellRunner.swift`) is injected into `CLIGitService` for all process spawning. For unit tests, a `MockGitService` returns canned responses without touching the filesystem.

**Unit tests for GitService** (inject `MockShellRunner`): cover all public methods. Non-obvious:
- `status()` XY field splitting: `MM` emits two entries, `M.` emits only staged, `.M` emits only unstaged.
- `status()` parses `u`-prefixed unmerged entries into a single unstaged `.unmerged` entry.
- `status()` rename entries (`2` prefix) consume the following NUL-separated original-path entry to keep the index aligned.
- `diff(paths:)` preserves staged rename metadata only when both the original and current path are passed.
- `discard()` restores tracked files via `git restore` but removes untracked files from disk.
- `discard()` with a staged rename must restore both the original and current path.
- `commitsAheadOfBase()` prefers `Project.remoteName/<base>` when that tracked ref exists and falls back to local `<base>` for local-only repos or partially configured remotes.
- `commitsAheadOfBase()` returns `0` when the compare command fails instead of throwing.
- `log()` preserves 4-line stride alignment even when a subject line is empty.

### File List Manager

`FileListManager` provides cached file listings for @-mention autocomplete in the chat input. It uses `GitService.listFiles()` for the underlying `git ls-files` call.

```swift
protocol FileListManager: Actor {  // Skep/Services/FileList/FileListManager.swift
    func files(for projectPath: String) async -> [String]
    func invalidateCache(for projectPath: String)
    func warmCache(for projectPath: String) async
}

actor GitFileListManager: FileListManager {  // Skep/Services/FileList/GitFileListManager.swift
    private var cache: [String: [String]] = [:]
    private let gitService: GitService

    init(gitService: GitService) {
        self.gitService = gitService
    }

    func files(for projectPath: String) async -> [String] {
        if let cached = cache[projectPath] { return cached }
        return await refresh(for: projectPath)
    }

    func invalidateCache(for projectPath: String) {
        cache.removeValue(forKey: projectPath)
    }

    func warmCache(for projectPath: String) async {
        if cache[projectPath] != nil { return }
        _ = await refresh(for: projectPath)
    }

    private func refresh(for projectPath: String) async -> [String] {
        let files = (try? await gitService.listFiles(in: projectPath)) ?? []
        cache[projectPath] = files
        return files
    }
}
```

Cache is invalidated from agent turn completion, manual refresh, and the diff viewer's local stage/unstage/discard actions; it is **not** invalidated on every filesystem event. Cache is warmed proactively when a thread is selected.

**Unit tests for FileListManager** (inject `MockGitService`): cover all public methods. Non-obvious:
- `files()` returns an empty array, not a thrown error, when `GitService.listFiles()` fails because the actor intentionally swallows that failure.

---
