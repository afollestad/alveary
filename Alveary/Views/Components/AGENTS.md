## Shared Components

General shared controls live here. Narrower scopes:

- `Accent/AGENTS.md`: `AppAccentFill`, accent-derived `NSColor`.
- `AppKit/AGENTS.md`: shared AppKit-only primitives.
- `Markdown/AGENTS.md`: `AppMarkdown*`, inline labels, code palettes.
- `TabChips/AGENTS.md`: `SelectableTabChip`, `TabChipButtonStyle`.
- `TextInput/AGENTS.md`: `AppTextEditor`, `AppKitTextView`.
- `ResponsivePaneHeader` owns the header chrome for every middle-pane screen; screen wrappers own their action labels, callbacks, and primary/secondary emphasis.
    - **Choose the arrangement by fit, never by a width threshold.** `PaneHeaderArrangement` is a ladder — action labels, then the filter chips, then the search field — and `ViewThatFits` takes the first rung that holds. A threshold cannot work here: the five headers mix these parts differently, so one number collapses controls that had room on most of them, and per-screen numbers drift out of step with their own content.
    - **Design for widths below `RightPaneWidthPolicy.minimumMainPaneWidth`.** That constant is a *preference*, not a floor: `bounds(availableWidth:)` yields it to the right pane's own minimum once the window cannot satisfy both, so a middle pane at ~250 points is reachable with the sidebar and right pane open. Anything sized for 420 will clip in a normal window.
    - **The last rung may refuse nothing.** Rungs above it size actions to content, because a rung that does not fit is simply rejected; the last one has no fallback, so it drops that `fixedSize`, truncates the filter dropdown's label, and caps unbounded labels (`ArchivedScreenHeader`). The row is also leading-anchored, so a width below even that rung spills trailing-only rather than centring the overflow for the enclosing pane to clip at both ends — which cut the filter control in half.
    - **A trailing control capped by `frame(maxWidth:)` must be trailing-aligned.** The cap is a reservation, not the control's width, so a short label leaves slack inside the frame that reads as a gap between the control and the header's trailing inset.
    - Selection stays view-model-owned. `PaneHeaderFilter` erases options to `PaneHeaderFilterItem` values, so options need not be `CaseIterable`; screens bridge a `Binding` as they already did.
- `OcticonImage` renders the vendored Primer Octicons as template images. Fixed-canvas 16px/24px artwork does not size by font, so every call site passes its own glyph box; tint comes from the ambient `foregroundStyle` so button-style hover/disabled states still apply.
    - Vendor the 16px variant beside SF Symbols; its strokes match SF weight, while 24px artwork renders visibly thinner at the same frame.
    - Even 16px artwork under-fills its canvas beside a same-size SF Symbol — a 16pt box gives `FileDiffOcticon` 14.0 points of ink against `terminal`'s 18.5 — so a mixed row wants a glyph box a couple of points larger than the font size; the primary toolbar uses `PrimaryToolbarMetrics.octiconSize` 18.
    - Add each vendored icon to `Alveary/Resources/PrimerOcticonsAttribution.txt`.
- `AppKitAnchoredPopover` (via `appKitPopover(isPresented:preferredEdge:content:)`) is the popover for content that must take **keyboard** focus. SwiftUI's `.popover` cannot: AppKit keeps the popover a child window of the presenter, so focus APIs report success while typing and ⌘V still reach the parent's first responder.
    - The fix is `window.parent?.removeChildWindow(window)` **before** `makeKeyAndOrderFront`, one runloop turn after `show(relativeTo:)` — earlier and AppKit re-attaches underneath.
    - **Never order its window from `updateNSView`.** Show and close both defer a runloop turn: SwiftUI runs `updateNSView` inside a Core Animation commit, and ordering there raised `NSViewBridgeErrorException` and crashed. Binds any representable that orders windows.
    - Its anchor view is flipped on purpose: `NSPopover` resolves `preferredEdge` in the anchor's coordinate space, so an unflipped anchor opens `.maxY` *upward*. Keep it flipped so the edge reads in screen terms.
    - Do not "fix" a non-typing popover with focus retries or key-claim loops; they cannot win against the child-window relationship. Live `NSPopover` host tests are banned (see `AlvearyTests/AGENTS.md`), so this path is verified by hand.
- `SecondaryClickTarget` reports right/control-clicks through an AppKit local event monitor, because SwiftUI has no secondary-click gesture and `contextMenu` is too late for act-on-mouse-down callers and wrong for non-menu responses. Apply it as an `overlay`/`background`; the monitor returns the event unchanged and the view's `hitTest` returns nil — the view must never claim clicks itself, or the placement silently eats the control's left-clicks.

### Right-Pane Lane

- `ResizableRightPane` owns the shared horizontal right-pane lane, width clamp, whole-point width snapping (both live drags and `effectiveWidth`; a fractional pane width makes AppKit-backed scroll content pixel-align a point short of its trailing inset while non-scrolling siblings keep the exact edge), cursor, accessibility adjustment, and drag-end persistence callback. Key its handle/content by presentation identity (destination and generation) so a route change cannot reuse local state after reopening. Carry the presentation generation through delayed closes so a stale collapse cannot discard a reopened target.
  - Keep presentation in its animatable layout: one progress value must place a fixed-width pane and reserve the matching main-content width. Do not animate the pane's width or use a render offset for AppKit-backed controls.
  - Keep pointer-drag width transient inside the shared component and publish the routed width binding only on commit. Root-level width writes on every mouse event rebuild the full `ContentView` hierarchy.
  - Resolve observable presentation generations inside the component body, never its initializer, so draft mutations do not become root `ContentView` observation dependencies.
  - Render a resolved non-nil presentation identity immediately; retain the stored identity only for exit animation. This prevents active target content from appearing under a stale route identity before `onChange` runs.
  - Reverse an in-flight collapse through the same presentation progress animation when another destination appears; never snap the lane back to its full width. **The one exception is a replacement that lands before the collapse has been drawn**, which `RightPanePresentationPolicy.reveal(...)` answers as `.immediate`: the lane never visibly left full width, so animating it back reads as an unprompted slide. That is the Git changes footer's back stack — closing a pull-request pane reveals the Diff Viewer request it was masking in the same update — and it restores progress inside a disabled-animation transaction instead.
    - **Track that with the `unrenderedCollapse` marker, never the progress value.** `beginDismissal` writes `presentationProgress = 0` *synchronously* (the animation only interpolates what is drawn), so by the time the replacement arrives the value already reads as fully collapsed and cannot distinguish a requested collapse from a watched one. The component sets the marker in `beginDismissal` and retires it after the first drawn frame; `reveal(...)` is pure and unit-tested in `ContentViewLayoutTests`.
  - Disable resize-handle hover, cursor, hit-testing, and accessibility feedback while the pane is sliding. A moving handle can otherwise synthesize hover under a stationary pointer.
  - Close actions deactivate their target, retain target-specific content through the slide-out, then discard that captured generation. External route changes may still hide a pane directly while preserving cached feature sessions.

### Pane Insets And Chrome

- `PaneHeaderLayout.height` keeps every middle-pane screen header and single-line contextual headers at 64 points so their bottom hairlines align; `.verticalPadding` (14) is shared for the same reason.
- `PaneHeaderLayout.leadingInset` (20) and `.trailingInset` (21) are the shared horizontal edges for pane headers *and* the scroll content beneath them; reference the constants, never a literal — the trailing 21 is deliberately not 20, and copied or invented numbers left rows visibly short of the header's action buttons before this was unified.
  - A new pane screen sets its content `EdgeInsets` from `PaneHeaderLayout`, and any new header — including hand-rolled ones that skip `ResponsivePaneHeader` — does the same. Changing either constant shifts every surface, so re-record the pane screen snapshots.
- `ContextualPaneLayout.horizontalInset` is 16 on *both* sides of detail/right panes, and it is the *visible* inset: `RightPaneResizeHandle` trailing-aligns its divider flush with the pane edge, because a centered line adds ~4pt of resize lane and makes 16pt read as 20. Do not shrink one side for the lane. Apply the inset through `contextualPaneHorizontalInsets()` or `ContextualPaneLayout.contentInsets(vertical:)` so every surface moves together, and re-record the pane baselines on change.
  - Keep `ContextualPaneHeader` at 16 points of vertical padding. `ContextualPaneFooter` places its note above equal-width actions, stacking full-width only when the pane is too narrow.
- `AppScrollIndicatorLayout.interactiveTrailingClearance` (28) is the minimum distance from a scroll view's trailing edge to an **interactive** control's trailing edge: the overlay scroller's grab region reaches past the visible 17pt lane — controls 3pt clear still dropped clicks while 11pt clear never did. Its dual `appKitHorizontalOverflowScrollbarReserve` reserves end-of-content space and only fires for legacy scrollers.
    - **Keep the number repo-owned; never derive it from `NSScroller.preferredScrollerStyle`.** The lane width changes across macOS releases (desyncing snapshots between machines), and the preferred style would let a user setting move layout. `AppScrollIndicatorLayoutTests` fails fast if the lane outgrows the clearance.
    - **Spend the clearance inside existing chrome, not as visible gaps.** Deepen a card's interior trailing padding or pad a whole trailing column; shrunken rows and floated lone controls read as misalignment, and `.contentMargins(.trailing, …, for: .scrollContent)` insets *all* content.
- **Every bar-backed pane footer goes through `contextualPaneFooterChrome()`.** It owns the whole strip — insets, vertical padding, `.bar` fill, and the top hairline — and its vertical padding is deliberately a file-private constant, because three surfaces had hand-rolled the chrome to 16/12/10 before unification. Do not re-inline or promote it; `ContextualPaneLayout.contentInsets(vertical:)` is *scroll content* only. `SnapshotTests+PaneFooterChrome.swift` is the parity gate.

### Pane Focus Restoration

- When an `EmptyStateView` action can invoke a contextual pane, give it a distinct action focus ID and pass the screen's action-focus binding so dismissal returns focus to that exact button instead of its duplicate header action.
- Before restoring contextual-pane focus, resolve the cached invoking ID against the screen's currently rendered triggers. Search, filtering, refreshes, or mutations can remove the original control while the nonmodal pane is open; fall back to the persistent header action instead of assigning an unmounted focus ID.
- `CommentReactionBar` is the GitHub-style reaction strip (toggle chips + circled smiley opening the emoji picker popover). It is provider-agnostic — callers supply `CommentReaction`/`CommentReactionOption` values and a toggle callback; an empty options list hides the add affordance.

## Status Spinners

- Use `StatusIndicatorSpinner` for fixed-size status spinner slots: the 8pt status-dot slots (sidebar rows, tab chips) and the 16pt `PrimaryToolbarProgressSlot`. Do not shrink `ProgressView` into dot slots.
- `PaneRefreshIconButton` is the shared header refresh control (Skills, MCP, Pull Requests): the icon action button swaps to a 14pt working spinner inside the same 30pt footprint while a refresh is in flight, so layout never shifts.
- AppKit surfaces use the `AppKit/AppKitStatusIndicatorSpinner` twin instead of `NSProgressIndicator` — task-list rows and the host-tool link card's disclosure slot today.
  Keep the two rings visually matched (track at 25% alpha, 0.7 arc, same spin period).
  AppKit tool-row loading is the scoped exception: it pulses summary text instead of showing a trailing spinner.
- Working spinners are `.secondary` gray, not blue — the spinning shape carries the "working" signal; blue stays reserved for `.waitingForUser` dots. See **Status Dot Colors** in `Alveary/Views/AGENTS.md`.
- Only `rotationEffect` animates; the frame stays fixed so busy/idle swaps cannot change row or chip layout.
- Snapshot determinism comes from the `statusSpinnerAnimationsDisabled` environment key, set by the shared snapshot hosts. `\.accessibilityReduceMotion` is get-only and cannot be injected in tests; the spinner still reads it for real reduce-motion users. The AppKit twin needs no hook: its spin is a presentation-only `CABasicAnimation`, so snapshots render the static model layer.

## Disabled Cursor

- Use `blockedCursorOverlay(when:)` for disabled SwiftUI controls that should show the macOS blocked cursor. AppKit text editors use `showsDisabledCursor` instead.

## Selectable Rows

- `SelectableRowModifier` in `SelectionRowBackground.swift` owns press highlight and action through one `DragGesture(minimumDistance: 0)`.
- Keep the movement guard so long clicks still fire but drags do not.
- Do not replace it with `.onTapGesture`; macOS drops long-held taps after the press highlight appears.
- Keep the sibling `.accessibilityAction { action() }` so VoiceOver activation works.
- Keep the pending-selection state for click releases; it bridges mouse-up to model publication so rows do not visually flash clear before becoming selected.
- Pass a stable row identity when selectable rows can be inserted, removed, or reordered so transient press/pending state cannot leak into recycled `List` rows.
- Keep selectable row background insets at their 10pt defaults unless a surface must compensate for host chrome to hit a measured visual edge.
- **Fade a row through `appSelectionRowBackground(opacity:)`, not an outer `.opacity`.** The fill is published via `listRowBackground`, which SwiftUI hoists out of the row's own render tree, so an outer `.opacity` dims the row's content while leaving a selected row's accent fill fully opaque. Pass the same value to both.

## Split Buttons

- Use `SplitActionButton` for one primary click target plus a trailing caret menu.
- The left side runs the selected option; the menu only changes selection.
- Reuse the shared chrome instead of hand-rolling an `HStack` divider and menu.
- Keep SwiftUI `Menu` out of the chrome. The component uses AppKit `NSMenu` to avoid snapshot indicator leaks and height inflation.
- `emphasis` picks the same fills as `primaryActionButtonStyle()` / `secondaryActionButtonStyle()` / `destructiveActionButtonStyle()` — including the destructive variant's white label, which the divider and hover overlay follow — `systemImage` is optional (text-only labels for pane footers), and `expandsHorizontally` fills an even-split footer half. Two accent-filled buttons in one row breaks the single-accent-voice rule — a split button standing beside a primary action takes `.secondary`.
- **Metrics and fills come from `ActionButtonMetrics` / `ActionButtonTint` in `ActionControls.swift`.** The split button draws its own background because the fill has to span the divider and caret, so only the tokens can be shared — do not re-inline the control-size tables or a literal tint, or the split button drifts from the plain buttons beside it.
- **The primary side needs an explicit `contentShape(Rectangle())`.** That shared fill sits on the outer `HStack`, so the primary `Button`'s own label is unbacked — and a `.plain` button hit-tests its label's shape, not its frame. Without the content shape only the text glyphs took clicks while the rest of the pill looked interactive. `ProminentActionButtonBody` needs no equivalent because its background is applied *to* the padded label, which is hit-testable on its own.

## Expandable Headers

- Use `AppHeaderToggle` for compact expand/collapse headers that need the AppKit mouse fallback.
- Pair `withAnimation(appExpansionAnimation)` with `.appExpansionAnimationOverride(value:)` so header toggles and surrounding lazy-list reflow share timing.

## Hover Info Popups

- Use `AppHoverInfoIcon` / `AppKitHoverInfoButton` for `info.circle` help affordances instead of plain `.help(...)` when the app needs the shared hover tooltip behavior.
- Keep hover tooltip content unpainted inside native `NSPopover` chrome so the system owns the background, opacity, shadow, and arrow.
- Keep info icons visually stable: center them relative to the adjacent label text and use the shared muted gray treatment regardless of the parent row's enabled or selected state.
- Keep tooltip sizing content-led but bounded. Short text should wrap content width, long text should wrap within the shared maximum width, and content should use balanced horizontal/vertical insets inside the native popover.
- Keep an open tooltip stable across unrelated parent updates. Rebuild its popover only when the displayed help text changes, and preserve the full wrapped text height.
- Prefer placing the tooltip to the trailing side of the icon when there is horizontal room, falling back to vertical placement only when needed.
- Preserve accessibility value/help on the info button so the hover tooltip does not replace screen-reader help.
