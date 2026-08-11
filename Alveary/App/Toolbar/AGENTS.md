## App Toolbar

These instructions cover `Alveary/App/Toolbar/` — the top-right `PrimaryToolbarButtonGroup` and its buttons, the project-actions slot, the leading window title and main-pane header, and `AppWindowToolbarConfigurator`. Routing a button's action is `Alveary/App/Routing/AGENTS.md`; the shortcut a button's tooltip renders is `Alveary/App/Shortcuts/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: the group's reserved width and trailing-aligned capsule, `PrimaryToolbarGroupWidth`, `PrimaryToolbarPullRequestSlot` and the project-action slot, `PrimaryToolbarMetrics.octiconSize`, `ToolbarProjectActionsSelection`, `refreshToolbarProjectActions`, `AppWindowToolbarConfigurator`, and the pull-request button's status, draft-artwork, and back-stack helpers each carry theirs.

### The Button Group

- **Optical spacing is measured, not chosen** — `PrimaryToolbarOpticalSpacing` points here for the procedure its compile-time values came from, and `PrimaryToolbarGlyphInk` runs the same measurement at runtime for the project-action strip. Derive a value from the recorded `primary_toolbar_button_group_*` baselines by thresholding ink columns, never from a screen-measuring tool: edge detection drops the pull-request glyph's small trailing circle and over-reports that gap by ~`2.5` points. Changing a toolbar glyph, `octiconSize`, or `iconFont` means redoing it; `ContentViewProjectActionsTests+ToolbarMetrics` holds the result against the baselines.
    - **Buy room with spacing alone.** Boxes, hover selectors, and hit targets all stay at `iconButtonSize` — never shrink a box or let two selectors overlap to fit another button.
- **Keep every animation curve in `PrimaryToolbarMetrics`**, so diff text, diff width, terminal status, hover, and press feedback cannot drift apart.
- **A toolbar glyph takes its color from the button style**, never a local `foregroundStyle` — a locally tinted glyph freezes through hover and disabled states.
    - **The pull-request status glyph is the one exception**, because with exactly one linked pull request the status *is* the information and a neutral glyph cannot say merged versus closed. Do not generalize it to other toolbar glyphs.

### Project Actions

- **A still-open failed project-action tab outranks a later success.** The terminal button's completion icon stays failed while any such tab remains open, even once the newest batch succeeds.

### The Diff Viewer Button

- **Keep stats in the button.** Green `+N` / red `-N` stay here rather than in transcript or composer chrome, which would alter composer height, invalidate lazy transcript row hit testing, and leave stale bottom space.
- **The button summarizes the working tree, whatever the pane shows.** The pane may switch between current changes and commits; the button's stats, loading, and visibility never follow it. `Alveary/Views/DiffViewer/AGENTS.md` points here rather than restating this.
- **Keep stats alive while the pane is hidden.** Hidden-pane selection changes still switch the diff view model with `scope: .toolbarStatsOnly`; do not clear the view model on hide. Full pane payloads load when the pane shows.
- **Use the resolved route for lifecycle, never the raw request.** Only a rendered `.diff` route enables filesystem watching or `.full` loads — a contextual pane may be masking the request, and a masked request must not drive labels, animation, or heavy loading. Async child flows call a root-lived scope resolver immediately before switching diff targets, because a render-time visibility `Bool` goes stale across suspensions.

### Window Title And Header

- **The visible title is a custom leading `.navigation` toolbar item.** Keep the scene's own `Window("Alveary", id: MainWindowPresenter.sceneID)` title intact and remove only its rendering with `.toolbar(removing: .title)`, then derive the visible title from `AppState.selectedSidebarItem`.
- **Match transcript edges without changing height.** `MainPaneToolbarLayout` completes the system edge inset so app-owned content lands on `transcriptScrollLeadingInset` / `transcriptScrollTrailingInset` — horizontal padding only, never vertical padding or a height frame on the header.
- **Keep title typography native-sized.** Plain destinations and project names render semibold `.title3`; thread names render through `AppMarkdownInlineLabel` at the same style and weight.
- **Keep conversation creation thread-scoped.** The title-adjacent `+` uses the mounted `ThreadDetailView`'s focused-scene `newConversationAction`, stays hidden before initial setup, and remains visible-but-disabled while creation is blocked. `Alveary/App/Shortcuts/AGENTS.md` owns why that focused value must be `Equatable`.
