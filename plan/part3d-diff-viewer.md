# Part 3d: Diff Viewer

Diff viewer pane, `DiffViewerViewModel`, file watching, staging/unstaging, and agent-directed commit/PR actions. Continues from Part 3c.

## Implementation Status

- [x] `DiffViewerViewModel` is implemented in the repo, including repository rebinding, refresh coalescing, FSEvents/poll watcher management, staged/untracked diff loading, contextual action discovery, and rename-aware discard expansion.
- [x] Focused regression coverage exists in `SkepTests/ViewModels/DiffViewerViewModelTests.swift` for the non-obvious refresh, diff-selection, cache, and contextual-action behaviors.
- [ ] Manual validation gate remains for integrated watcher behavior once the real pane UI exists.

## Diff Viewer (Uncommitted Changes)

The diff viewer is the **right pane**, toggleable via menu bar. It shows uncommitted changes for the selected thread's worktree so users can review what the agent changed, stage or revert specific files, and then ask the agent to commit or open a PR.

When the pane is visible but the current middle-pane selection has no thread/worktree context (`Skills`, `MCP`, project settings, or the first-run empty state), the pane stays open and renders a lightweight placeholder instead of auto-hiding. In that state, `DiffViewerViewModel.clear()` has already stopped file watching and emptied the diff/file state, so staging and contextual actions are hidden or disabled until the user selects a thread again.

The repo binding for this pane is a real value, not just a loose collection of scalars: later phases should treat `directory`, `baseRef`, `remoteName`, and `conversationIds` as one coherent snapshot so FSEvents rebinding, ahead-of-base checks, and agent-status filtering cannot drift apart after a thread switch.

### Layout

Resizable vertical layout with file list header and scrollable diff content:

```
┌─────────────────────────────────────────────────┐
│  🔵   ◇ Commit   📋 📄 📊   +6 -6   ⚙        │ ← toolbar: status, action, stats
├─────────────────────────────────────────────────┤
│  Unstaged  1  ▾                          ···    │ ← file list header
│  ┌─────────────────────────────────────────────┐│
│  │ .../cart/LocalBrandLocationCartView.kt  +6-6││ ← file row (expandable)
│  │  ┌─ 138 unmodified lines ─────────────────┐││
│  │  │ 139   ) {                              │││
│  │  │ 140     item(key = ITEM_KEY_SUMMARY) { │││
│  │  │ 141       Text(                        │││
│  │  │▐142-    Modifier.padding(top = 32.dp,  │││ ← red = removed
│  │  │▐142+    Modifier.padding(top = 32.dp,  │││ ← green = added
│  │  │ 143       text = model.summaryLabel,   │││
│  │  │▐144-    color = ArcadeTheme.colors...  │││
│  │  │▐144+    color = ArcadeTheme.colors...  │││
│  │  │ 145       style = ArcadeTheme.typog... │││
│  │  │  ┌─ 127 unmodified lines ────────────┐ │││ ← collapsed unchanged
│  │  │ 275   val themedUrl = selection...     │││
│  │  │▐278-    Modifier.size(82.dp)           │││
│  │  │▐279-    .clip(RoundedCornerShape(16.dp)│││
│  │  │▐278+    Modifier.size(88.dp)           │││
│  │  │▐279+    .clip(RoundedCornerShape(12.dp)│││
│  │  └────────────────────────────────────────┘││
│  └─────────────────────────────────────────────┘│
│                                                 │
│                    ↻ Revert all    + Stage all   │ ← actions
└─────────────────────────────────────────────────┘
```

- **File list**: changed files grouped by staged/unstaged. Color-coded status (yellow=modified, green=added, red=deleted, blue=renamed, orange=unmerged) with change-count badges. Staged rename rows render as `old/path.ext → new/path.ext` instead of only the destination path.
- **Inline diff**: expanding a file shows unified diff with line numbers, collapsed unchanged regions, and red/green highlighting.
- **Bottom actions**: Revert all / Stage all. Individual files via context menu or checkboxes.

### Data Flow

1. **File change detection**: Watch recursively via `FSEvents` (`FSEventStreamCreate` with `kFSEventStreamCreateFlagFileEvents`). `DispatchSource.makeFileSystemObjectSource` only watches a single directory, unsuitable for project trees. Debounce (~500ms) before re-running `git status --porcelain=v2 -z`. Preserve the debounced callback's changed paths so selected-diff refreshes can tell whether the currently expanded file was actually touched.
2. **File list update**: Parse status output into changed files with status (modified, added, deleted, renamed, untracked). Staged renames carry both `path` (destination) and `originalPath` (source); unstaged filesystem moves still appear as a deleted source row plus an untracked destination row until both sides are staged.
3. **Diff fetching**: On file expand, use `GitService.diff(paths:scope:in:)` for tracked files (`.staged` vs `.unstaged` based on the selected row) and `GitService.syntheticAddedDiff(for:in:)` for untracked files. Ordinary tracked rows pass `[file.path]`; staged rename rows pass `[originalPath, path]` so git emits `rename from` / `rename to` headers instead of collapsing to an add-only diff for the destination path.
4. **Parsing**: `DiffParser.parse()` (`Skep/DiffParser/DiffParser.swift`) returns `[DiffFile]`.
5. **Rendering**: Each `DiffFile` maps to an expandable file row in the diff viewer.

   ```
   DiffFile → file row header (display path, linesAdded/linesDeleted badge)
     └── DiffHunk[] → rendered sequentially within the expanded file
           ├── collapsed context region ("N unmodified lines")
           │     └── DiffLine where .context, grouped into collapsible runs
           ├── DiffLine(.deleted) → red background, old line number only
           ├── DiffLine(.added)   → green background, new line number only
           └── DiffLine(.context) → no highlight, both line numbers
   ```

   **Rename presentation**: when `FileStatus.status == .renamed` and `originalPath` is present, show `originalPath → path` in both the right-pane row header and the compact changed-files strip above the chat input.

   **Context collapsing**: consecutive `.context` lines between changed regions collapse into "N unmodified lines". First/last 3 context lines stay visible; the middle collapses until expanded.

   **Line numbers**: two-column gutter (old left, new right). Added lines show new only; deleted lines show old only; context shows both.

   **Hunk headers**: if `DiffHunk.header` is non-nil (for example `func validateToken()`), show it as a dim label above the hunk.

   **Binary files**: `DiffFile.isBinary == true` renders "Binary file changed" instead of a line-level diff.

   **Syntax highlighting**: Textual's `diff` language mode (Prism.js) provides token-level coloring on top of the red/green backgrounds.

### Staging and Unstaging

- **Per-file**: checkbox calls `git add -- <path>` or `git reset HEAD -- <path>`. For a staged rename row, the checkbox targets the destination path; unstaging splits the rename back into a deleted source row plus an untracked destination row on the next refresh.
- **Bulk**: "Stage All" / "Unstage All" for the entire list or per group. Bulk stage operates on the full visible path set (or `git add -A` for the whole worktree), so a deleted-source + untracked-destination move collapses into one staged rename row on the next refresh. Bulk unstage resets the staged entries (destination path for rename rows, or an equivalent whole-index reset such as `git reset HEAD -- .`), which splits staged rename rows back into deleted + untracked rows on refresh.
- **File revert**: `gitService.discard(paths:in:)` with confirmation dialog. Ordinary tracked files use `git restore`; staged rename rows expand to both `[originalPath, path]` before discard so the source filename is restored and the destination path is removed; untracked files are deleted from disk.
- **Revert All / group revert**: build the discard path list from every targeted row, but expand each staged rename row to both `[originalPath, path]` before calling `gitService.discard(paths:in:)`.

Refresh the file list after each staging operation.

### Agent-Directed Commit and PR Actions

V1 does **not** open dedicated commit or PR modals. The right-pane toolbar exposes one contextual action and routes it through the normal conversation send pipeline instead of running `git commit`, `git push`, or `gh pr create` directly from app UI.

Build-order note: the Phase 6 **Diff Viewer** step owns the repository-side pieces here — `contextualAction`, disabled-state rules, canned request text, and the `DiffViewerPane` callback surface. The concrete cross-pane handoff (`DiffViewerPane` tap → `AppState.pendingDiffAction` → matching `ConversationView.queueOrSend()`) is wired later in the **App Layout** step, once both `ContentView` and `ConversationView` exist.

When the active thread has uncommitted changes:
- The toolbar action is **Commit**.
- Tapping it sends a canned user request into the selected conversation via the same `queueOrSend()` path as typed chat input.
- If at least one file is staged, the request should explicitly ask the agent to commit the **currently staged changes** so manual staging boundaries remain meaningful.
- If nothing is staged yet, the request can ask the agent to review and commit the current worktree changes.

When the worktree is clean:
- If the current branch already has an open PR, the toolbar action is **View PR** and opens the PR URL.
- If the branch is ahead of the configured base branch and no open PR exists, the toolbar action is **Open PR**.
- **Open PR** also routes through the selected conversation. The canned request should tell the agent to open a PR for the current branch against `baseRef`, pushing or publishing the branch first if needed.
- There is no separate **Push** action in V1. Publishing the branch is part of the agent's work when fulfilling an **Open PR** request.

Action-dispatch rules:
- `DiffViewerViewModel` stays repository-scoped. It decides **which** action is available, but it does **not** send messages to the agent itself.
- `DiffViewerPane` is rendered by `ContentView`, so `ContentView` is the concrete owner for these action closures. On tap, it resolves the currently selected thread and conversation from `AppState`, snapshots the canned request text plus the target conversation's `PersistentIdentifier`, and stores that identifier-only payload in `AppState.pendingDiffAction`.
- The matching `ConversationView` consumes that one-shot `pendingDiffAction` request only when its `conversation.persistentModelID` matches the snapshotted target conversation, then re-checks the live request/selection immediately before calling `queueOrSend()`. This closes the scheduling gap where a task launched from an earlier matching state could otherwise still send after `ContentView` or `ThreadDetailView` had already canceled the request.
- If the user changes side-conversation tabs or middle-pane selection before that matching conversation consumes the request, the request is canceled (`ThreadDetailView` owns the tab-switch cancellation, `ContentView` owns the broader middle-pane cancellation). Diff-viewer actions are UI intents for the currently visible chat, not durable background jobs.
- If no thread or selected conversation is available for the active middle-pane state, **Commit** / **Open PR** stay disabled rather than guessing a destination. This includes Settings: the pane can keep showing preserved diff state there, but Settings has replaced `ConversationView`, so agent-directed actions are disabled until a thread view is active again. `View PR` remains available because it opens a URL directly.
- Because the action uses the existing send pipeline, the established busy-state, queued-message, token-gating, and retry semantics all apply automatically.
- After the agent acts, the diff viewer learns about new commit/PR state through the usual refresh paths: `.agentStatusChanged`, FSEvents, focus refresh, and manual refresh.

### Auto-Refresh

### Refresh Decision Matrix

| Trigger | Invalidate `FileListManager` cache? | Invalidate PR cache? | Reload selected diff? | Why |
|---|---|---|---|---|
| `.fsEvent(changedPaths:)` | No | No | Only if the selected row changed identity or one of `changedPaths` touches the selected file / rename pair | Avoid expensive diff reloads for unrelated writes |
| `.agentTurnCompleted` | Yes | Yes | Only if the selected row changed identity; file-content reloads normally arrive through the paired `.fsEvent` refresh | Avoid re-running a large selected diff immediately after every turn when FSEvents already carries the path-level invalidation |
| `.localGitMutation` | Yes | No | Yes | Stage / unstage / discard change file rows and contextual action, but they do not change PR state |
| `.appBecameActive` | No | No | Yes | External tools may have changed the repo while the app was unfocused |
| `.manual` | Yes | Yes | Yes | Explicit user intent should bypass warm caches and refresh current repo state |
| `.idlePoll` | No | No | Only if the selected row changed identity | Background freshness check without thrashing shell work |
| `.threadSwitch` | No | Only when the directory changes | Only when the directory changes | Same-directory switches only update `activeConversationIds`; repo state, watcher, and selected diff stay warm |

Example: a same-worktree conversation switch keeps the watcher, PR state, and selected diff warm; only `activeConversationIds` changes.

### DiffViewerViewModel

Drives the right pane. Scoped to the **active thread's working directory**; switching threads refreshes with the new worktree path.

`DiffViewerViewModel` owns repository state only (`files`, selected diff, contextual action, watcher lifecycle, git actions, PR cache). It does not own chat drafts or send prompts to the agent. Agent-directed commit/open-PR dispatch belongs to the pane owner so this view model stays independent from `ConversationViewModel`.

```swift
@MainActor @Observable
class DiffViewerViewModel {  // Skep/ViewModels/DiffViewerViewModel.swift
    private struct RefreshRequest {
        let reason: RefreshReason
        let invalidateFileListCache: Bool
        let invalidatePRCache: Bool
    }

    /// Retained by the FSEvents stream so the callback can safely recover both the
    /// owning view model and the root directory without touching @MainActor state
    /// from the background callback queue.
    private final class WatchContext {
        let owner: DiffViewerViewModel
        let rootDirectory: String

        init(owner: DiffViewerViewModel, rootDirectory: String) {
            self.owner = owner
            self.rootDirectory = rootDirectory
        }
    }

    private(set) var files: [FileStatus] = []
    private(set) var selectedFile: FileStatus?
    private(set) var parsedDiff: DiffFile?
    private(set) var rawDiffContent: String = ""
    private(set) var contextualAction: ContextualAction = .none
    private(set) var gitError: String?
    private(set) var activeDirectory: String?
    private var activeConversationIds: Set<String> = []
    private var baseRef: String = "main"
    private var remoteName: String?
    private let gitService: GitService
    private let gitHubService: GitHubService
    private let fileListManager: FileListManager
    private let agentsManager: any AgentsManager
    private var cachedPRs: [PRInfo]?
    private var prCacheTime: Date = .distantPast
    private static let prCacheTTL: TimeInterval = 60
    private var inFlightRefresh: Task<Void, Never>?
    private var pendingRefresh: RefreshRequest?
    private var directoryGeneration: UInt64 = 0
    private var fileSelectionGeneration: UInt64 = 0
    private var fsEventStream: FSEventStreamRef?
    private var fsEventQueue: DispatchQueue?
    private var watchContextRetain: Unmanaged<WatchContext>?
    private var debounceTask: Task<Void, Never>?
    private var pollTask: Task<Void, Never>?
    private var watchingEnabled = false
    private var pendingChangedPaths: Set<String> = []
    private var agentStatusObserver: NSObjectProtocol?
    private var appActiveObserver: NSObjectProtocol?
    private var appWillTerminateObserver: NSObjectProtocol?

    enum ContextualAction {
        case none
        case commit
        case openPR
        case viewPR(url: String)
    }

    enum RefreshReason {
        case fsEvent(changedPaths: Set<String>)
        case agentTurnCompleted
        case appBecameActive
        case localGitMutation
        case manual
        case idlePoll
        case threadSwitch
    }

    init(gitService: GitService, gitHubService: GitHubService, fileListManager: FileListManager, agentsManager: any AgentsManager) {
        self.gitService = gitService
        self.gitHubService = gitHubService
        self.fileListManager = fileListManager
        self.agentsManager = agentsManager

        agentStatusObserver = NotificationCenter.default.addObserver(
            forName: .agentStatusChanged, object: nil, queue: .main
        ) { [weak self] notification in
            Task { @MainActor in
                guard let self, let dir = self.activeDirectory else { return }
                if let conversationId = notification.userInfo?["conversationId"] as? String {
                    guard self.activeConversationIds.contains(conversationId) else { return }
                    // Notification payloads are only invalidation hints; re-read the manager's
                    // current status so out-of-order `.idle` / `.neutral` deliveries do not
                    // trigger a heavy diff refresh while the conversation is already busy again.
                    if self.agentsManager.status(for: conversationId) == .busy {
                        return
                    }
                }
                await self.refreshAndInvalidateFileList(in: dir, reason: .agentTurnCompleted)
            }
        }

        appActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self, let dir = self.activeDirectory else { return }
                await self.refresh(in: dir, reason: .appBecameActive)
            }
        }

        appWillTerminateObserver = NotificationCenter.default.addObserver(
            forName: .appWillTerminate, object: nil, queue: nil
        ) { [weak self] _ in
            // `applicationWillTerminate` posts this immediately before a synchronous
            // main-thread shutdown wait, so this observer must tear down inline rather
            // than enqueue another main-actor task that may never get a turn to run.
            MainActor.assumeIsolated {
                self?.tearDown()
            }
        }
    }

    func switchToDirectory(_ directory: String, baseRef: String = "main", remoteName: String?, conversationIds: Set<String>) async {
        activeConversationIds = conversationIds
        guard directory != activeDirectory || baseRef != self.baseRef || remoteName != self.remoteName else {
            // Same-directory fast path: only `activeConversationIds` changes.
            return
        }
        let directoryChanged = directory != activeDirectory
        directoryGeneration &+= 1
        fileSelectionGeneration &+= 1
        self.baseRef = baseRef
        self.remoteName = remoteName
        stopWatching()
        activeDirectory = directory
        if directoryChanged {
            files = []
            selectedFile = nil
            parsedDiff = nil
            rawDiffContent = ""
            contextualAction = .none
            gitError = nil
        }
        invalidatePRCache()
        if watchingEnabled {
            startWatching(directory)
        }
        await refresh(in: directory, reason: .threadSwitch)
    }

    func setWatchingEnabled(_ enabled: Bool) {
        guard watchingEnabled != enabled else { return }
        watchingEnabled = enabled
        guard let activeDirectory else { return }
        if enabled {
            startWatching(activeDirectory)
        } else {
            stopWatching()
        }
    }

    func clear() {
        directoryGeneration &+= 1
        fileSelectionGeneration &+= 1
        stopWatching()
        activeDirectory = nil
        files = []
        selectedFile = nil
        parsedDiff = nil
        rawDiffContent = ""
        contextualAction = .none
        gitError = nil
        invalidatePRCache()
    }

    func refresh(in directory: String, reason: RefreshReason) async {
        let generation = directoryGeneration
        let refreshedFiles: [FileStatus]
        let refreshedError: String?
        do {
            refreshedFiles = try await gitService.status(in: directory)
            refreshedError = nil
        } catch {
            refreshedFiles = []
            refreshedError = "Git status failed: \(error.localizedDescription)"
        }
        guard isCurrentBinding(directory: directory, generation: generation) else { return }
        files = refreshedFiles
        gitError = refreshedError
        if refreshedError != nil {
            contextualAction = .none
            // Preserve the currently rendered diff, but do not spend more shell work on
            // follow-on diff fetches while `git status` is the authoritative error state.
            return
        }

        let action = await determineAction(in: directory)
        guard isCurrentBinding(directory: directory, generation: generation) else { return }
        contextualAction = action
        await refreshSelectedDiffIfNeeded(in: directory, generation: generation, reason: reason)
    }

    /// Invalidates the @-mention file cache before refreshing, and invalidates the PR
    /// cache only when the trigger can actually change branch/PR state.
    func refreshAndInvalidateFileList(in directory: String, reason: RefreshReason) async {
        if reason != .localGitMutation {
            invalidatePRCache()
        }
        await fileListManager.invalidateCache(for: directory)
        await refresh(in: directory, reason: reason)
    }

    func selectFile(_ file: FileStatus, in directory: String) async {
        selectedFile = file
        let bindingGeneration = directoryGeneration
        fileSelectionGeneration &+= 1
        let selectionGeneration = fileSelectionGeneration
        do {
            let raw: String
            if file.status == .untracked {
                raw = try await gitService.syntheticAddedDiff(for: file.path, in: directory)
            } else {
                raw = try await gitService.diff(
                    paths: diffPaths(for: file),
                    scope: file.isStaged ? .staged : .unstaged,
                    in: directory
                )
            }
            guard isCurrentBinding(directory: directory, generation: bindingGeneration),
                  fileSelectionGeneration == selectionGeneration,
                  selectedFile?.path == file.path,
                  selectedFile?.isStaged == file.isStaged else {
                return
            }
            guard raw.utf8.count <= 5 * 1024 * 1024 else {
                rawDiffContent = ""
                parsedDiff = nil
                gitError = "Diff preview exceeded 5MB"
                return
            }
            let parsed = await Task.detached(priority: .utility) {
                DiffParser.parse(raw).first
            }.value
            guard isCurrentBinding(directory: directory, generation: bindingGeneration),
                  fileSelectionGeneration == selectionGeneration,
                  selectedFile?.path == file.path,
                  selectedFile?.isStaged == file.isStaged else {
                return
            }
            rawDiffContent = raw
            parsedDiff = parsed
            gitError = nil
        } catch {
            guard isCurrentBinding(directory: directory, generation: bindingGeneration),
                  fileSelectionGeneration == selectionGeneration,
                  selectedFile?.path == file.path,
                  selectedFile?.isStaged == file.isStaged else {
                return
            }
            rawDiffContent = ""
            parsedDiff = nil
            gitError = "Diff failed: \(error.localizedDescription)"
        }
    }

    func stage(paths: [String], in directory: String) async throws {
        try await gitService.stage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func unstage(paths: [String], in directory: String) async throws {
        try await gitService.unstage(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    func discard(paths: [String], in directory: String) async throws {
        try await gitService.discard(paths: paths, in: directory)
        await refreshAndInvalidateFileList(in: directory, reason: .localGitMutation)
    }

    private func diffPaths(for file: FileStatus) -> [String] {
        if file.status == .renamed, let originalPath = file.originalPath {
            return [originalPath, file.path]
        }
        return [file.path]
    }

    private func determineAction(in directory: String) async -> ContextualAction {
        if !files.isEmpty { return .commit }

        let baseBranch = baseBranchForDirectory(directory)
        async let aheadTask = (try? gitService.commitsAheadOfBase(baseBranch: baseBranch, remoteName: remoteName, in: directory)) ?? 0
        async let currentBranchTask = try? gitService.currentBranch(in: directory)
        async let prsTask = cachedListPRs(in: directory)

        let ahead = await aheadTask
        let currentBranch = await currentBranchTask
        let prs = await prsTask

        if let pr = prs.first(where: { $0.state == "OPEN" && $0.headRefName == currentBranch }) {
            return .viewPR(url: pr.url)
        }
        if ahead > 0 {
            return .openPR
        }
        return .none
    }

    private func refreshSelectedDiffIfNeeded(in directory: String, generation: UInt64, reason: RefreshReason) async {
        guard isCurrentBinding(directory: directory, generation: generation) else { return }
        guard let selectedFile else { return }
        let selectedAnchor = selectedFile.originalPath ?? selectedFile.path
        let updatedSelection = files.first {
            $0.path == selectedFile.path && $0.isStaged == selectedFile.isStaged
        } ?? files.first {
            $0.path == selectedFile.path
        } ?? files.first {
            ($0.originalPath ?? $0.path) == selectedAnchor && $0.isStaged == selectedFile.isStaged
        } ?? files.first {
            ($0.originalPath ?? $0.path) == selectedAnchor
        }

        guard isCurrentBinding(directory: directory, generation: generation) else { return }
        guard let updatedSelection else {
            self.selectedFile = nil
            parsedDiff = nil
            rawDiffContent = ""
            return
        }

        let selectionChanged = updatedSelection.path != selectedFile.path
            || updatedSelection.originalPath != selectedFile.originalPath
            || updatedSelection.isStaged != selectedFile.isStaged
            || updatedSelection.status != selectedFile.status

        let shouldReloadDiff: Bool
        switch reason {
        case .manual, .appBecameActive, .localGitMutation:
            shouldReloadDiff = true
        case .threadSwitch, .agentTurnCompleted:
            shouldReloadDiff = selectionChanged
        case .idlePoll:
            shouldReloadDiff = selectionChanged
        case .fsEvent(let changedPaths):
            let selectedPaths = Set([updatedSelection.path, updatedSelection.originalPath].compactMap { $0 })
            shouldReloadDiff = selectionChanged || !changedPaths.isDisjoint(with: selectedPaths)
        }

        guard shouldReloadDiff else {
            self.selectedFile = updatedSelection
            return
        }

        await selectFile(updatedSelection, in: directory)
    }

    private func cachedListPRs(in directory: String) async -> [PRInfo] {
        if let cached = cachedPRs,
           Date().timeIntervalSince(prCacheTime) < Self.prCacheTTL {
            return cached
        }
        do {
            let prs = try await gitHubService.listPRs(in: directory)
            cachedPRs = prs
            prCacheTime = Date()
            return prs
        } catch {
            return cachedPRs ?? []
        }
    }

    private func invalidatePRCache() {
        cachedPRs = nil
        prCacheTime = .distantPast
    }

    private func isCurrentBinding(directory: String, generation: UInt64) -> Bool {
        activeDirectory == directory && directoryGeneration == generation
    }

    private func baseBranchForDirectory(_ directory: String) -> String {
        baseRef
    }

    private func startWatching(_ directory: String) {
        let paths = [directory] as CFArray
        var context = FSEventStreamContext()
        let retainedContext = Unmanaged.passRetained(WatchContext(owner: self, rootDirectory: directory))
        watchContextRetain = retainedContext
        context.info = retainedContext.toOpaque()
        let stream = FSEventStreamCreate(
            nil,
            { _, info, numEvents, eventPaths, _, _ in
                guard let info else { return }
                let watchContext = Unmanaged<WatchContext>.fromOpaque(info).takeUnretainedValue()
                let changedPaths = DiffViewerViewModel.extractChangedPaths(
                    eventPaths: eventPaths,
                    count: numEvents,
                    rootDirectory: watchContext.rootDirectory
                )
                Task { @MainActor in watchContext.owner.fsEventsDidFire(changedPaths: changedPaths) }
            },
            &context,
            paths,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.5,
            UInt32(kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagUseCFTypes)
        )
        if let stream {
            let queue = DispatchQueue(label: "com.afollestad.skep.fsevents", qos: .utility)
            FSEventStreamSetDispatchQueue(stream, queue)
            FSEventStreamStart(stream)
            fsEventStream = stream
            fsEventQueue = queue
        } else {
            retainedContext.release()
            watchContextRetain = nil
        }
        pollTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let self, let dir = self.activeDirectory else { continue }
                await self.refresh(in: dir, reason: .idlePoll)
            }
        }
    }

    private func stopWatching() {
        debounceTask?.cancel()
        debounceTask = nil
        pollTask?.cancel()
        pollTask = nil
        if let stream = fsEventStream, let queue = fsEventQueue {
            FSEventStreamStop(stream)
            queue.sync { FSEventStreamInvalidate(stream) }
            FSEventStreamRelease(stream)
            fsEventStream = nil
            fsEventQueue = nil
            watchContextRetain?.release()
            watchContextRetain = nil
        }
    }

    private func fsEventsDidFire(changedPaths: Set<String>) {
        debounceTask?.cancel()
        pendingChangedPaths.formUnion(changedPaths)
        debounceTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(500))
            guard let dir = activeDirectory else { return }
            let paths = pendingChangedPaths
            pendingChangedPaths = []
            await refresh(in: dir, reason: .fsEvent(changedPaths: paths))
        }
    }

    private static func extractChangedPaths(eventPaths: UnsafeRawPointer?, count: Int, rootDirectory: String?) -> Set<String> {
        guard let rootDirectory,
              let eventPaths else { return [] }
        let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue() as? [String] ?? []
        let rootPrefix = rootDirectory.hasSuffix("/") ? rootDirectory : rootDirectory + "/"
        return Set(paths.prefix(count).map { absolutePath in
            absolutePath.hasPrefix(rootPrefix) ? String(absolutePath.dropFirst(rootPrefix.count)) : absolutePath
        })
    }

    func tearDown() {
        if let agentStatusObserver {
            NotificationCenter.default.removeObserver(agentStatusObserver)
            self.agentStatusObserver = nil
        }
        if let appActiveObserver {
            NotificationCenter.default.removeObserver(appActiveObserver)
            self.appActiveObserver = nil
        }
        if let appWillTerminateObserver {
            NotificationCenter.default.removeObserver(appWillTerminateObserver)
            self.appWillTerminateObserver = nil
        }
        stopWatching()
    }

    deinit {
        tearDown()  // safety net if a future owner forgets the explicit teardown path
    }
}
```

**Used by**: `DiffViewerPane` (right pane).

Minimal screen signature:

```swift
struct DiffViewerPane: View {  // Skep/Views/DiffViewer/DiffViewerPane.swift
    let viewModel: DiffViewerViewModel
    let areAgentActionsEnabled: Bool
    let onCommitRequested: () -> Void
    let onOpenPRRequested: () -> Void
}
```

### Refresh Triggers and Caching

| Trigger | What refreshes | Method | Source |
|---|---|---|---|
| FSEvents callback (debounced 500ms) | File list + contextual action; selected diff only if the expanded file's path was among the changed paths | `refresh(reason: .fsEvent)` | Filesystem watcher on the active directory |
| Agent turn completion | File list + contextual action + PR cache + @-mention file cache; selected diff only if the refreshed row binding changed | `refreshAndInvalidateFileList(reason: .agentTurnCompleted)` | `.agentStatusChanged` notification for the currently selected thread. The observer re-reads `agentsManager.status(for:)` and only refreshes when the latest authoritative status is no longer `.busy`. FSEvents usually covers file-content diff invalidation separately. |
| App window regains focus | File list + contextual action; selected diff revalidated once | `refresh(reason: .appBecameActive)` | `NSApplication.didBecomeActiveNotification` |
| Stage/unstage/discard | File list + contextual action + @-mention file cache; selected diff revalidated once | `refreshAndInvalidateFileList(reason: .localGitMutation)` | After the git operation completes |
| Thread switch | Same-directory: update `activeConversationIds` only. Directory/base-ref change: rebind context, refresh repo state, reload selected diff, and restart watcher as needed. | `switchToDirectory()` | `ContentView.updateDiffViewer()` |
| First-time worktree creation for the selected thread | Rebind from project root to the new worktree directory + refresh | `switchToDirectory()` | `ConversationView` observes the selected thread's effective working directory |
| Side-conversation create/select within the same selected thread | Refresh the same-directory binding so `activeConversationIds` includes the new conversation | `switchToDirectory()` | `ThreadDetailView.createConversation()` |
| Right pane shown/hidden | Watcher only | `setWatchingEnabled()` | `ContentView` toggles FSEvents without clearing the current file summary |
| Manual refresh | File list + contextual action + PR cache + @-mention file cache; selected diff revalidated once | `refreshAndInvalidateFileList(reason: .manual)` | User gesture |
| Idle fallback poll (60s) | File list + contextual action; selected diff only if the row binding changed since the last refresh | `refresh(reason: .idlePoll)` | Timer as a safety net for missed FSEvents |

**Caching strategy**:
- **File list** (`files`): not cached; each refresh re-runs `git status`.
- **Cross-directory rebinding**: immediately clears the visible file list/diff content before the new refresh completes, preventing stale rows from the previously selected thread from remaining interactive.
- **Contextual action**: recomputed every refresh. `listPRs` is a repo-scoped 60s TTL cache. Invalidating that cache on agent turn completion, manual refresh, and cross-directory thread switches keeps the toolbar from lagging after an agent-created commit or PR without throwing away warm PR data for same-directory switches or local stage/unstage/discard actions.
- **@-mention file cache**: invalidated before the shared diff/chat refresh completes. The chat composer re-reads `FileListManager.files(for:)` on demand when the `@` popup opens, so post-turn suggestions do not stay pinned to an older `git ls-files` snapshot.
- **Background refresh coalescing**: non-manual refresh triggers (`fsEvent`, `appBecameActive`, `agentTurnCompleted`, `idlePoll`) are single-flight per active directory. Model this explicitly with a queued `RefreshRequest` state (`reason` + cache-invalidation booleans) so overlapping FSEvents / focus / agent-status pings fold into the next pass instead of launching overlapping `git status` / `gh pr list` work.
- **Selected file diff**: after each file-list refresh, the selection is re-resolved by current path / `originalPath`. A new `git diff` runs only when that binding changed, when the trigger is an explicit revalidation point, or when debounced `FSEvents` touched the selected path.
- **Status-failure behavior**: if `git status` fails, `gitError` becomes authoritative for that refresh. The diff viewer clears `contextualAction` to `.none`, skips PR queries, and skips selected-diff re-fetches so stale repo state cannot overwrite the error surface.
- **FileListManager cache**: invalidated on turn completion, manual refresh, and local diff-viewer git actions; not on every FSEvents callback.

**Unit tests** (inject `MockGitService`, `MockGitHubService`, `MockFileListManager`): cover public methods, `contextualAction` state, cache behavior, and generation-guarded async updates. Non-obvious:
- `selectFile()` uses `syntheticAddedDiff()` for untracked files and keeps rename metadata by diffing both `[originalPath, path]`.
- `refresh()` re-resolves the selected file across stage/unstage regrouping and rename path changes, and clears the selection only when the underlying change disappears.
- `refresh(reason: .fsEvent)` does not re-fetch the selected diff when the changed-path set does not intersect the expanded file.
- `refresh(reason: .idlePoll)` skips a redundant selected-diff fetch when the row binding is unchanged.
- `selectFile()` fails fast with a stable "Diff preview exceeded 5MB" state instead of parsing/rendering huge diffs on the main UI path.
- If `gitService.status(in:)` fails, `refresh()` sets `gitError`, clears `contextualAction` to `.none`, and skips both PR lookup and follow-on selected-diff fetches for that cycle.
- Per-row discard for a staged rename expands to both the original and current path before calling `gitService.discard(paths:in:)`.
- `determineAction()` returns `.commit` whenever `files` is non-empty, `.viewPR(url:)` only for the current branch's open PR, `.openPR` when the branch is ahead of base with no open PR, and `.none` otherwise.
- `refreshAndInvalidateFileList()` invalidates PR cache before refreshing so an agent-created PR can flip the toolbar from **Open PR** to **View PR** on the next turn-completion refresh.
- `refreshAndInvalidateFileList(reason: .localGitMutation)` keeps the warm PR cache instead of clearing it; staging-only operations must not trigger a fresh `gh pr list`
- `determineAction()` compares `HEAD` against `remoteName/baseRef` when that tracked ref exists, and falls back to local `baseRef` for local-only repos
- Same-directory `threadSwitch` updates `activeConversationIds` without rerunning git/gh work, preserving the selected diff
- A transient `gitHubService.listPRs(in:)` failure reuses the warm cache; without one it returns `[]` for that refresh and leaves the cache cold.
- Background refresh bursts coalesce behind one in-flight refresh task plus the queued `RefreshRequest`; manual refresh still starts a fresh pass
- A stale `.agentStatusChanged` payload does not trigger a refresh while the authoritative `agentsManager.status(for:)` has already returned to `.busy`
- `switchToDirectory()` updates `activeConversationIds` before the same-directory fast path so agent-status filtering follows the newly selected thread even when the watcher and repo snapshot are reused untouched.
- Late `refresh(in:)` and `selectFile()` completions are ignored after a newer thread or file selection takes over.
- The FSEvents callback reads the watched root path from its retained `WatchContext`, not from `activeDirectory`, so the background callback never touches `@MainActor` state directly
- The `.appWillTerminate` observer tears down synchronously via `MainActor.assumeIsolated` instead of `Task { @MainActor ... }`, so watcher shutdown is not starved by `AppDelegate.applicationWillTerminate` blocking the main actor immediately afterward.
- `tearDown()` removes all NotificationCenter observers in addition to stopping FSEvents and polling; `deinit` calls it as a safety net

Note: FSEvents behavior is not unit-testable; cover it with manual/integration testing.

**Snapshot tests**: `DiffViewerPane` key states: placeholder, rename row rendered as `old → new`, collapsed context regions, and **Commit** / **Open PR** / **View PR** toolbar states.
