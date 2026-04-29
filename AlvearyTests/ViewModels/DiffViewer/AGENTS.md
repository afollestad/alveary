## Diff Viewer View-Model Tests

These instructions apply to tests under `AlvearyTests/ViewModels/DiffViewer/`.

- Keep `DiffViewerViewModelTests` companion files as extensions of the base suite, matching the repo-wide `+Topic` convention.
- Cover target-switch, cache, cancellation, delayed-loading, and selected-diff failure paths when changing `DiffWorkspaceStore` or `DiffViewerViewModel`.
