## View Models

These instructions apply to files under `Alveary/ViewModels/`.

- Keep view models as coordination layers: route UI intent, own observers/watchers, and delegate service-backed state to focused collaborators when state becomes shared or long-running.
- `DiffWorkspaceStore` is the single source of truth for Diff Viewer files, stats, selected diff content, loading state, and per-project/worktree stats caching.
    - **Preserve visible-state clearing.** Target switches must clear visible files, selected diff, and toolbar stats immediately without deleting cached stats for other targets.
    - **Guard async publishes.** Status, stats, and selected-diff tasks must check target/load generation or IDs before publishing so stale work cannot update a newer selection.
    - **Delay only indicators.** Start Git work immediately; delay only the toolbar/preview spinner visibility so quick loads do not flash.
