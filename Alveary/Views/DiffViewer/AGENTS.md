# Diff Viewer

These instructions cover the SwiftUI diff viewer pane under `Alveary/Views/DiffViewer/`.

## Sidebar-To-Pane Routing

Diff Viewer target construction lives under `Alveary/ViewModels/DiffViewer/`; view code should consume `DiffViewerViewModel` state instead of rebuilding project/worktree routing rules.

## Diff State And Loading

`DiffWorkspaceStore` owns file rows, selected-file preview state, toolbar stats, loading states, generation checks, and the in-memory stats cache. View code should render the published state directly.

- **Refresh the active target.** The pane refresh button should route through `forceRefreshActiveDiff()` so it refreshes the currently selected project/worktree and reloads the selected-file preview when one is active.
- **Acknowledge manual refresh immediately.** Keep pane refresh button feedback immediate and short-lived even when diff loading finishes before the delayed toolbar/preview spinners appear.
- **Delay visible loading indicators.** The store should start Git work immediately, but toolbar and selected-preview spinners should appear only after the configured grace period if the load is still active.
- **Show toolbar loading for any visible diff load.** The toolbar should replace `+N` / `-N` with a fixed-size spinner while either all-file stats or the selected-file preview diff is past the spinner grace period.
- **Keep preview pending neutral.** During the spinner grace period, the lower pane should avoid showing an empty/error preview for a diff that is still loading.

## File List Interaction

- **Keep right-click selection synchronous.** Context-menu selection uses an AppKit local event monitor so the clicked row is visibly selected before SwiftUI opens the menu. Do not route that first visual selection only through an async `Task`.
- **Drive the top divider from scroll offset.** The header divider should appear from the file list's y scroll offset, not row indices. `DiffViewerFileListScrollMonitor` finds the backing `NSScrollView` because SwiftUI `List` does not guarantee the monitor view is inside it.
- **Preserve top on inserts.** When the list is already at the top and rows are inserted above, keep scrolling to the new top without animation so the first row is not clipped under the header.

## File List Overlay Ordering

`DiffViewerFileListSection` layers three states on the same `.overlay`:
1. `isLoading` → spinner + "Loading changes…".
2. `files.isEmpty && isGitRepository` → "Working tree is clean".
3. `files.isEmpty && !isGitRepository` → "Git features unavailable".

Keep the `isLoading` branch first. `performRefresh` publishes `files` and flips `isLoadingFiles` in the same main-actor tick, so there is no interleaved frame where the clean state would leak through — but only if the overlay checks loading before emptiness.
