## Shared Components

General shared controls live here. Narrower scopes:

- `Accent/AGENTS.md`: `AppAccentFill`, accent-derived `NSColor`.
- `AppKit/AGENTS.md`: shared AppKit-only primitives.
- `Markdown/AGENTS.md`: `AppMarkdown*`, inline labels, code palettes.
- `TabChips/AGENTS.md`: `SelectableTabChip`, `TabChipButtonStyle`.
- `TextInput/AGENTS.md`: `AppTextEditor`, `AppKitTextView`.
- `CompactSearchPaneHeader` owns the fixed search/header chrome shared by Skills and MCP; screen wrappers own their action labels, callbacks, and primary/secondary emphasis.
- `ResizableRightPane` owns the shared horizontal right-pane lane, width clamp, whole-point width snapping (both live drags and `effectiveWidth`; a fractional pane width makes AppKit-backed scroll content pixel-align a point short of its trailing inset while non-scrolling siblings keep the exact edge), cursor, accessibility adjustment, and drag-end persistence callback. Key its handle/content by presentation identity (destination and generation) so a route change cannot commit the previous width domain or reuse local state after reopening. Carry the presentation generation through delayed closes so a stale collapse cannot discard a reopened target.
  - Keep presentation in its animatable layout: one progress value must place a fixed-width pane and reserve the matching main-content width. Do not animate the pane's width or use a render offset for AppKit-backed controls.
  - Keep pointer-drag width transient inside the shared component and publish the routed width binding only on commit. Root-level width writes on every mouse event rebuild the full `ContentView` hierarchy.
  - Resolve observable presentation generations inside the component body, never its initializer, so draft mutations do not become root `ContentView` observation dependencies.
  - Render a resolved non-nil presentation identity immediately; retain the stored identity only for exit animation. This prevents active target content from appearing under a stale route identity before `onChange` runs.
  - Reverse an in-flight collapse through the same presentation progress animation when another destination appears; never snap the lane back to its full width.
  - Disable resize-handle hover, cursor, hit-testing, and accessibility feedback while the pane is sliding. A moving handle can otherwise synthesize hover under a stationary pointer.
  - Close actions deactivate their target, retain target-specific content through the slide-out, then discard that captured generation. External route changes may still hide a pane directly while preserving cached feature sessions.
- `PaneHeaderLayout.height` keeps Skills, MCP, Scheduled, and single-line contextual headers at 64 points so their bottom hairlines align.
- `PaneHeaderLayout.leadingInset` (20) and `.trailingInset` (21) are the shared horizontal edges for pane headers *and* the scroll content beneath them. Both the header and the screen's content padding must reference these constants — never a literal.
  - **Why:** the trailing value is 21, not 20, so a content site that copies the leading number or picks its own padding leaves rows visibly short of the header's action buttons. Skills, MCP, Scheduled, and Archived all sat at a hardcoded 28 against 21-point headers until this was unified.
  - **How to apply:** a new pane screen sets its content `EdgeInsets` leading/trailing from `PaneHeaderLayout`, and any new header — including hand-rolled ones that do not wrap `CompactSearchPaneHeader` — does the same. Changing either constant shifts every surface at once, so re-record the pane screen snapshot baselines.
- `ContextualPaneLayout.horizontalInset` is 16 on *both* sides for the detail/right panes (Skills, MCP, Scheduled, Pull requests), and it is also the *visible* inset: `RightPaneResizeHandle` trailing-aligns its divider line so the line sits flush with the pane's frame edge (a centered line put ~4pt of resize lane between the divider and the pane, making 16pt of padding read as 20). Do not shrink one side to compensate for the lane, and keep the divider trailing-aligned — the two invariants together are what make padding equal visible inset. Apply the inset through `contextualPaneHorizontalInsets()` or `ContextualPaneLayout.contentInsets(vertical:)` so every surface moves together (and re-record the pane baselines when it changes). Keep `ContextualPaneHeader` at 16 points of vertical padding. `ContextualPaneFooter` places its note above equal-width actions, falling back to full-width stacked actions only when the pane is too narrow.
- When an `EmptyStateView` action can invoke a contextual pane, give it a distinct action focus ID and pass the screen's action-focus binding so dismissal returns focus to that exact button instead of its duplicate header action.
- Before restoring contextual-pane focus, resolve the cached invoking ID against the screen's currently rendered triggers. Search, filtering, refreshes, or mutations can remove the original control while the nonmodal pane is open; fall back to the persistent header action instead of assigning an unmounted focus ID.
- `CommentReactionBar` is the GitHub-style reaction strip (toggle chips + circled smiley opening the emoji picker popover). It is provider-agnostic — callers supply `CommentReaction`/`CommentReactionOption` values and a toggle callback; an empty options list hides the add affordance.

## Status Spinners

- Use `StatusIndicatorSpinner` for fixed-size status spinner slots: the 8pt status-dot slots (sidebar rows, tab chips) and the 16pt `PrimaryToolbarProgressSlot`. Do not shrink `ProgressView` into dot slots.
- `PaneRefreshIconButton` is the shared header refresh control (Skills, MCP, Pull Requests): the icon action button swaps to a 14pt working spinner inside the same 30pt footprint while a refresh is in flight, so layout never shifts.
- AppKit task-list rows use the `AppKit/AppKitStatusIndicatorSpinner` twin instead of `NSProgressIndicator`.
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
