## Pane Chrome And The Right-Pane Lane

These instructions cover `Alveary/Views/Components/Panes/` — `ResponsivePaneHeader` and the middle-pane screen header chrome, `ContextualPaneHeader` / `ContextualPaneFooter` and the insets every detail pane shares, and `ResizableRightPane`, the lane itself. What a route puts *in* the lane is `Alveary/App/Routing/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `ResponsivePaneHeader`'s degradation ladder, `PaneHeaderLayout`'s spacing constants, `ContextualPaneLayout` and `contextualPaneFooterChrome()`, `PaneRefreshIconButton`, `RightPanePresentationPolicy.reveal(...)`, and `RightPaneWidthPolicy.effectiveWidth` each carry theirs.

### Screen Headers

- **`ResponsivePaneHeader` owns the header chrome for every middle-pane screen**; screen wrappers own their action labels, callbacks, and primary/secondary emphasis, and bridge their own filter `Binding` — selection stays view-model-owned.
- **Design for widths below `RightPaneWidthPolicy.minimumMainPaneWidth`.** That constant is a *preference*, not a floor: `bounds(availableWidth:)` yields it to the right pane's own minimum once the window cannot satisfy both, so a middle pane at ~250 points is reachable with the sidebar and right pane open. Anything sized for 420 will clip in a normal window.
- **A new pane screen takes its header height and content insets from `PaneHeaderLayout`** — a hand-rolled header that skips `ResponsivePaneHeader` included — so bottom hairlines and row edges line up across screens. Changing a constant moves every surface; re-record the pane screen snapshots.

### Pane Insets And Chrome

- **Apply the contextual pane's inset through `contextualPaneHorizontalInsets()` or `ContextualPaneLayout.contentInsets(vertical:)`**, never a literal, so every surface moves together; re-record the pane baselines on change. `ContextualPaneHeader` stays at 16 points of vertical padding.
- **Every bar-backed pane footer goes through `contextualPaneFooterChrome()`** — insets, vertical padding, `.bar` fill, and top hairline in one modifier. Do not re-inline it or promote its private vertical constant; `SnapshotTests+PaneFooterChrome.swift` is the parity gate.
- **A pane's chromeless trailing glyphs center on `ContextualPaneLayout.trailingGlyphAxis`, never right-align.** Take the lane through `contextualPaneTrailingGlyphLane()`, or its `controlWidth:` overload for a wider chromeless control.
    - **A sub-point residual is the glyph's own side bearing, not a bug.** The lane centers the *frame*; an asymmetric glyph keeps its ink slightly off it (`chevron.right` lands 0.8pt out). Do not chase it with a nudge constant — that reintroduces exactly what the lane replaced.
    - **Inside a scroll view, widen the row's frame instead of padding the glyph** — negative padding leaves the glyph outside its own hit rect, unclickable. `diffPreviewViewportContentWidthFrame(trailingExtension:)` carries `AppHeaderToggle`'s content shape out with the caret.
    - An interactive control inside a scroll view still owes `AppScrollIndicatorLayout.interactiveTrailingClearance`; `Alveary/Views/Components/AGENTS.md` owns how to spend it.

### The Lane

- **Key `ResizableRightPane`'s handle and content by presentation identity** — destination plus generation — so a route change cannot reuse local state after reopening, and carry that generation through delayed closes so a stale collapse cannot discard a reopened target.
- **Keep presentation in one animatable progress value** that both places the fixed-width pane and reserves the matching main-content width. The pane's own width never animates, and the slide is layout placement — never an `.offset()` on AppKit-backed content, which moves the render without moving the view.
- **Resolve observable presentation generations inside the component body, never its initializer**, or a draft mutation becomes a root `ContentView` observation dependency.
- **Disable the resize handle's hover, cursor, hit-testing, and accessibility feedback while the lane is sliding.** A moving handle otherwise synthesizes hover under a stationary pointer.

### Focus Restoration

- **An `EmptyStateView` action that opens a contextual pane needs its own focus ID**, passed with the screen's action-focus binding, so dismissal returns focus to that button rather than to its duplicate header action.
- **Resolve a cached invoking ID against the currently rendered triggers before restoring focus** (`ContextualPaneFocusRestoration.resolve`): a search, a filter change, a refresh, or a mutation can unmount the original control while the nonmodal pane is open. `Alveary/ViewModels/AGENTS.md` owns when a dismissal may restore focus at all.
