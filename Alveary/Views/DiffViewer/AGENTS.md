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

## Diff State And Loading

`DiffWorkspaceStore` owns file rows, selected-file preview state, toolbar stats, loading states, generation checks, and the in-memory stats cache. `DiffViewerViewModel` should stay a coordinator for routing, watchers, contextual actions, and store delegation.

- **Clear visible target state on switches.** Project/thread switches must synchronously remove the previous target's visible toolbar stats, file rows, and selected diff before async Git work starts. Do not delete cached stats for other targets during this visible-state clear.
- **Cache stats by project/worktree.** Diff stats cache keys must include `projectPath`, optional `worktreePath`, `baseRef`, and `remoteName`; a base project and each active worktree can have different local changes.
- **Keep stats auxiliary.** Status refreshes should publish file rows first and start stats loading separately. If stats fail while status succeeds, clear visible stats and keep the pane usable instead of surfacing a Git error.
- **Evict only failed current stats.** Failed status or stats refreshes should remove that active target's cached stats, not unrelated project/worktree cache entries.
- **Refresh the active target.** The pane refresh button should route through `forceRefreshActiveDiff()` so it refreshes the currently selected project/worktree and reloads the selected-file preview when one is active.
- **Acknowledge manual refresh immediately.** Keep pane refresh button feedback immediate and short-lived even when diff loading finishes before the delayed toolbar/preview spinners appear.
- **Delay visible loading indicators.** The store should start Git work immediately, but toolbar and selected-preview spinners should appear only after the configured grace period if the load is still active.
- **Show toolbar loading for any visible diff load.** The toolbar should replace `+N` / `-N` with a fixed-size spinner while either all-file stats or the selected-file preview diff is past the spinner grace period.
- **Keep preview pending neutral.** During the spinner grace period, the lower pane should avoid showing an empty/error preview for a diff that is still loading.
- **Use generation guards.** Status, stats, and selected-file diff tasks must check the active target generation before publishing so stale work cannot update the toolbar or lower pane after a switch.

## File List Overlay Ordering

`DiffViewerFileListSection` layers three states on the same `.overlay`:
1. `isLoading` → spinner + "Loading changes…".
2. `files.isEmpty && isGitRepository` → "Working tree is clean".
3. `files.isEmpty && !isGitRepository` → "Git features unavailable".

Keep the `isLoading` branch first. `performRefresh` publishes `files` and flips `isLoadingFiles` in the same main-actor tick, so there is no interleaved frame where the clean state would leak through — but only if the overlay checks loading before emptiness.
