# Diff Viewer View Models

These instructions apply to Diff Viewer coordination and state under `Alveary/ViewModels/DiffViewer/`.

- `DiffViewerViewModel` coordinates routing, watchers, contextual actions, and store delegation. Keep durable Git-backed file/stat/diff state in `DiffWorkspaceStore`.
    - **Own commit mode state here.** Ahead commits, selected commit, parsed commit diffs, raw fallback text, and commit load/error state belong on `DiffViewerViewModel`, not in SwiftUI views.
    - **Keep commit file collapse transient.** Per-file collapse state belongs on `DiffViewerViewModel`, keyed by commit hash, pruned when commits are no longer ahead, and cleared on target switch.
    - **Guard commit async publishes.** Commit-list and commit-diff tasks must check the current target plus a generation/load id before publishing so stale work cannot update a newer project, worktree, or selected commit.
    - **Reload commits centrally.** Same-target workspace refreshes should refresh ahead commits from the view model only while commit mode is active; inactive same-target refreshes or discarded pending reloads should mark commits stale so the next commit-mode activation reloads. Commit-mode views should not independently reload from `workspaceRefreshRevision`.
    - **Avoid duplicate commit loads.** Ignore non-forced same-target commit loads when a list is already loading or loaded; thread-switch refreshes should not reload a list that was just requested for the new target.
    - **Coalesce commit reloads.** Forced workspace refreshes should queue one pending commit-list reload while a commit diff is loading instead of cancelling the visible diff task repeatedly; a pending reload should preserve an already loaded selected commit diff when that commit is still ahead.
    - **Preserve manual commit selection.** Selecting a commit while a same-target list reload is in flight should not stale or strand that list reload; when the refreshed list still contains the selected hash, keep that selection.
    - **Parse commit diffs before preview shaping.** Keep commit diff parsing independent from UI row limits; large-preview shaping belongs in the Diff Viewer views.
    - **Honor switch scope.** `switchToTarget(_:scope:)` with `.toolbarStatsOnly` loads status and toolbar stats but skips selected-diff work; callers use it while the diff pane is hidden. A later same-target `.full` switch must upgrade via `needsFullPaneRefresh` instead of deduping. Mark that flag before any stats-only refresh suspends, and order refresh requests so an older full completion cannot clear a newer hidden-refresh requirement.
    - **Deduplicate by workspace, not sidebar owner.** Project/thread routing into the same `DiffWorkspaceTarget` updates conversation ownership without reloading Git state. A different worktree target must clear and reload visible diff state even when the selected project or thread identity is unchanged.
- `DiffWorkspaceStore` is the single source of truth for Diff Viewer files, stats, selected diff content, loading state, and per-project/worktree stats caching.
    - **Preserve visible-state clearing.** Target switches must clear visible files, selected diff, and toolbar stats immediately without deleting cached stats for other targets.
    - **Guard async publishes.** Status, stats, and selected-diff tasks must check target/load generation or IDs before publishing so stale work cannot update a newer selection.
    - **Delay only indicators.** Start Git work immediately; delay only toolbar/preview spinner visibility so quick loads do not flash.
    - **Keep multi-selection separate.** `selectedFileKeys` owns batch selection, while `selectedFile` remains the single preview anchor. Reconcile keys after status refreshes and Git mutations.
- `DiffViewerSwitchTarget` is the pure sidebar-to-diff target factory.
    - **Prefer worktree paths.** Thread targets should use `worktreePath` over `project.path`; non-worktree threads fall back to the project path.
    - **Filter project conversations.** Project targets should include only live non-worktree conversations, plus threads whose `worktreePath` equals the project path.

## Image Previews

- **Preserve full identity keys.** Image preview cache/temp filenames must include the readable commit/content prefix, full diff path identity, old/new side, and a stable hash of the unsanitized identity so different folders or sanitized paths cannot collide.
- **Avoid extra Git work.** Current-change diff loading should request `HEAD` only after a parsed diff is known to be raster-previewable.
