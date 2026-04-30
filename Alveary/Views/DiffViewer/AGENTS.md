# Diff Viewer

These instructions cover the SwiftUI diff viewer pane under `Alveary/Views/DiffViewer/`.

## Sidebar-To-Pane Routing

Diff Viewer target construction lives under `Alveary/ViewModels/DiffViewer/`; view code should consume `DiffViewerViewModel` state instead of rebuilding project/worktree routing rules.

## Diff State And Loading

`DiffWorkspaceStore` owns file rows, selected-file preview state, toolbar stats, loading states, generation checks, and the in-memory stats cache. View code should render the published state directly.

- **Delay visible loading indicators.** The store should start Git work immediately, but toolbar and selected-preview spinners should appear only after the configured grace period if the load is still active.
- **Show toolbar loading for any visible diff load.** The toolbar should replace `+N` / `-N` with a fixed-size spinner while either all-file stats or the selected-file preview diff is past the spinner grace period.
- **Keep preview pending neutral.** During the spinner grace period, the lower pane should avoid showing an empty/error preview for a diff that is still loading.

## Split Pane Layout

- **Share vertical resizing.** Diff Viewer modes that show top and bottom panes should use `DiffViewerVerticalSplit`
  instead of duplicating split-height, resize-handle, or accessibility behavior.
- **Persist split positions by mode.** Current changes and commits have separate saved split fractions; do not reuse one mode's resize position for the other.

## Pane Modes

- **Expose mode through the header menu.** The title-only control is the pane-mode menu:
    - Keep the full rounded rectangle as the hit target.
    - Keep the visual label title-only, but keep the accessibility value carrying the current mode and active path.
    - Keep the rounded border, matching pane background, light pressed state, and right-aligned caret obvious.
    - Let it expand to the available header width before the action buttons instead of assigning a fixed width.
- **Keep header actions compact.** Header actions should be icon-only buttons with text in `.help(...)` and accessibility labels:
    - Keep the mode menu and icon buttons the same height.
    - Keep 6pt spacing between the mode menu and action buttons.
    - Keep action buttons inside `DiffViewerHeaderActionContainer`.
    - Animate the container's reserved width so the mode menu width changes smoothly when actions appear or disappear.
- **Keep toolbar stats independent.** The main toolbar button always summarizes working-tree changes, regardless of the selected pane mode.
- **Hide non-PR actions outside current changes.** `Commit`, `Stage`, `Unstage`, and `Discard` are current-change actions. Commit mode should only render PR actions (`Create PR` or `View PR`), and the action container should animate to zero width when no PR action is available.

## Commits Mode

- **Preserve commit row shape.** Commit rows should stay one ellipsizing line with the bold short hash, 6pt spacing, then the title, with 4pt vertical content padding.
- **Keep commit selection singular.** File lists support modifier/range multi-selection; commit lists should disable native multi-selection and select only one commit at a time.
- **Preserve visible commits while refreshing.** If a same-target commit reload is loading or fails with existing commits still available, keep those rows visible; only use list-level loading/error states when there are no commits to preserve.
- **Flatten file diff previews.** Current changes and commits should render through `FlattenedDiffPreview`, which supports one or more `DiffFile` values and keeps file headers, hunk headers, and line rows in one lazy row stream. Large flattened row models should be prepared off the main actor.
- **Render explicit states.** Show separate loading, empty-ahead-commits, Git/error, selected-diff loading, diff-too-large, raw fallback, and no-diff states.

## File List Interaction

- **Keep file-row dots consistent.** File-list rows should render fixed-size colored `Circle` views like thread rows; staged rows are green and unstaged rows are secondary.
- **Expose full file paths.** File-list row help text should be `FileStatus.path` so truncated paths remain discoverable from any hover point on the row.
- **Keep right-click selection synchronous.** Context-menu selection uses an AppKit local event monitor so the clicked row is visibly selected before SwiftUI opens the menu. Do not route that first visual selection only through an async `Task`.
- **Drive the top divider from scroll offset.** The header divider should appear from the file list's y scroll offset, not row indices. `DiffViewerFileListScrollMonitor` finds the backing `NSScrollView` because SwiftUI `List` does not guarantee the monitor view is inside it.
- **Preserve top on inserts.** When the list is already at the top and rows are inserted above, keep scrolling to the new top without animation so the first row is not clipped under the header.

## File List Overlay Ordering

`DiffViewerFileListSection` layers three states on the same `.overlay`:
1. `isLoading` → spinner + "Loading changes…".
2. `files.isEmpty && isGitRepository` → "Working tree is clean".
3. `files.isEmpty && !isGitRepository` → "Git features unavailable".

Keep the `isLoading` branch first. `performRefresh` publishes `files` and flips `isLoadingFiles` in the same main-actor tick, so there is no interleaved frame where the clean state would leak through — but only if the overlay checks loading before emptiness.
