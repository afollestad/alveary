# Diff Viewer

These instructions cover `Alveary/Views/DiffViewer/` — where the diff viewer's state comes from, and the modals lifted to this level.

The two surfaces have their own scope: `Pane/` (the pane, its modes, header, lists, and footer) and `Preview/` (`FlattenedDiffPreview` and its row stream, including the comment rows the pull-request pane renders through it).

## Diff State

Routing and durable state both live under `Alveary/ViewModels/DiffViewer/` — `DiffViewerSwitchTarget` builds targets from the sidebar selection, and `DiffWorkspaceStore` owns file rows, selected-file preview state, toolbar stats, load states, generation checks, and the stats cache. View code renders that published state and rebuilds neither.

- **The main toolbar button is not this scope's.** Its stats, loading, and visibility belong to `Alveary/App/Toolbar/AGENTS.md`, which owns why they summarize working-tree changes regardless of the selected pane mode. Do not restate that here.

## Modals

- **The create modal shares the commit modal's shape.** `DiffCreatePullRequestModal` reuses `DiffBranchSelectionMenu` (extracted from the commit modal — do not fork a second copy), `AppTextField` for the title, and the BlockInputKit `PullRequestCommentEditor` at four visible lines for the description; blank fields generate on submit through the model. The base branch is never selectable there — a pull request cannot merge base into base — so on-base checkouts default to `+ New branch` with the prefixed name.
