# Diff Viewer

These instructions cover the diff viewer pane, its view model, and the sidebar-to-pane routing helpers under `Alveary/Views/DiffViewer/` and `Alveary/App/ContentView+DiffViewerRouting.swift`.

## Sidebar-To-Pane Routing

The routing switch lives in `ContentView+DiffViewerRouting.swift` and delegates all target construction to `DiffViewerSwitchTarget.forThread(_:)` / `DiffViewerSwitchTarget.forProject(_:)`. Keep the factories pure so they stay testable from `DiffViewerSwitchTargetTests`.

- **`forThread` prefers `worktreePath` over `project.path`.**
    - **Why:** a thread with a worktree must read its own diffs, not the project root. A thread without a worktree falls back to the project path because that's where its agent writes.
    - **How to apply:** never pass the project path directly when building a thread target. Let the factory decide.
- **`forProject` filters candidate threads to `archivedAt == nil && (worktreePath == nil || worktreePath == project.path)` when building `conversationIds`.**
    - **Why:** `DiffViewerViewModel.activeConversationIds` gates the `.agentStatusChanged` observer's rescan. Worktree-threads mutate a separate directory on disk, so their completion signals must not trigger a rescan of the project root — they'd just be a wasted `git status`. External mutations to the project root (merges, CLI commits) still come through the FSEvents watcher.
    - **How to apply:** production routing should pass fetch-backed live thread rows into `candidateThreads` and fetch-backed IDs into `candidateConversationIDs` instead of walking `project.threads` / `thread.conversations` from SwiftUI selection state. If you add a new thread-location flag (e.g. "side-worktree"), extend this filter rather than the observer. Keep the "what counts as an agent that writes here" decision in one place.

## Loading State

`DiffViewerViewModel.isLoadingFiles` is a one-shot flag that the file list section reads to show the "Loading changes…" overlay ahead of the empty-state overlay.

- **Set `isLoadingFiles = true` only when `switchToDirectory` detects `directoryChanged`.**
    - **Why:** same-directory refreshes (baseRef/remoteName changed, or a refresh after a git mutation) keep the existing file list on screen. Flipping the flag would flash the spinner over content the user can still read correctly.
- **Clear `isLoadingFiles = false` at the end of `performRefresh` and in `clear()`.** Do not clear it in `switchToDirectory` — a stale refresh whose generation no longer matches early-returns from `performRefresh` before the clear, and the next `switchToDirectory` has already re-set the flag for the new binding.
- **Publish line stats with file refreshes.** `DiffViewerViewModel.diffStats` is the toolbar's `+N` / `-N` source and should update from the same generation-checked refresh that publishes `files`. Keep stats auxiliary: if the stats command fails while status succeeds, show empty stats instead of surfacing a diff-viewer error.

## File List Overlay Ordering

`DiffViewerFileListSection` layers three states on the same `.overlay`:
1. `isLoading` → spinner + "Loading changes…".
2. `files.isEmpty && isGitRepository` → "Working tree is clean".
3. `files.isEmpty && !isGitRepository` → "Git features unavailable".

Keep the `isLoading` branch first. `performRefresh` publishes `files` and flips `isLoadingFiles` in the same main-actor tick, so there is no interleaved frame where the clean state would leak through — but only if the overlay checks loading before emptiness.
