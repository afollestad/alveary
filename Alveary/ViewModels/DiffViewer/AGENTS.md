# Diff Viewer View Models

These instructions apply to Diff Viewer coordination and state under `Alveary/ViewModels/DiffViewer/`.

- `DiffViewerViewModel` coordinates routing, watchers, contextual actions, and store delegation. Keep durable Git-backed file/stat/diff state in `DiffWorkspaceStore`.
- `DiffWorkspaceStore` is the single source of truth for Diff Viewer files, stats, selected diff content, loading state, and per-project/worktree stats caching.
    - **Preserve visible-state clearing.** Target switches must clear visible files, selected diff, and toolbar stats immediately without deleting cached stats for other targets.
    - **Guard async publishes.** Status, stats, and selected-diff tasks must check target/load generation or IDs before publishing so stale work cannot update a newer selection.
    - **Delay only indicators.** Start Git work immediately; delay only toolbar/preview spinner visibility so quick loads do not flash.
    - **Keep multi-selection separate.** `selectedFileKeys` owns batch selection, while `selectedFile` remains the single preview anchor. Reconcile keys after status refreshes and Git mutations.
- `DiffViewerSwitchTarget` is the pure sidebar-to-diff target factory.
    - **Prefer worktree paths.** Thread targets should use `worktreePath` over `project.path`; non-worktree threads fall back to the project path.
    - **Filter project conversations.** Project targets should include only live non-worktree conversations, plus threads whose `worktreePath` equals the project path.
