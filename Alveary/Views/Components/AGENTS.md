## Shared Components

General shared controls live here. Narrower scopes:

- `Alveary/Views/Components/Accent/AGENTS.md`: `AppAccentFill`, accent-derived `NSColor`.
- `Alveary/Views/Components/AppKit/AGENTS.md`: shared AppKit-only primitives.
- `Alveary/Views/Components/Markdown/AGENTS.md`: `AppMarkdown*`, inline labels, code palettes.
- `Alveary/Views/Components/Panes/AGENTS.md`: pane header/footer chrome, insets, the right-pane lane.
- `Alveary/Views/Components/TabChips/AGENTS.md`: `SelectableTabChip`, `TabChipButtonStyle`.
- `Alveary/Views/Components/TextInput/AGENTS.md`: `AppTextEditor`, `AppKitTextView`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `ActionIcon` and `ActionButtonLabel`, `ActionButtonMetrics` / `ActionButtonTint`, `Octicon` and `OcticonImage`, `AppKitAnchoredPopover`, `AppOverflowMenu` / `AppOverflowMenuMetrics` / `AppOverflowMenuRow`, `AdaptiveCardGridLayout` / `adaptiveCardGridColumnCount(...)` / `adaptiveCardGridReflow(...)`, `appSelectableCard(...)` / `AppSelectableCardBackground`, `KeepAliveTabContainer`, `SecondaryClickTarget`, `appSelectableRow(...)`, `AppScrollIndicatorLayout`, `StatusIndicatorSpinner`, `CommentReactionBar`, and `SplitActionButton`'s `emphasis` and `isBusy` each carry theirs.

## Icons

- **A menu row's `Label` needs `.labelStyle(.titleAndIcon)`.** macOS menu rows default to a *title-only* style, so a bare `Label(_:systemImage:)` silently renders glyph-less. Octicons do render there, as `Label { Text(…) } icon: { OcticonImage(…) }` with that same style; `DiffBranchSelectionMenu`'s branch rows are the proof.
- **`GitBranchOcticon16` is the glyph wherever the app means a repository or a branch.** `arrow.triangle.branch` / `arrow.trianglehead.branch` stay reserved for the *worktree* concept and for the project-action symbol picker, which persists SF Symbol names on disk.
- Add each vendored octicon to `Alveary/Resources/PrimerOcticonsAttribution.txt`.

## Scroll Indicator Clearance

- **Spend `AppScrollIndicatorLayout.interactiveTrailingClearance` inside existing chrome, not as visible gaps.** Deepen a card's interior trailing padding or pad a whole trailing column; shrunken rows and floated lone controls read as misalignment, and `.contentMargins(.trailing, …, for: .scrollContent)` insets *all* content.
- **It governs scroll-view interiors only.** A pane header, tab row, or footer has no scroller floating over it, so its chrome takes the trailing glyph lane instead — see `Alveary/Views/Components/Panes/AGENTS.md`.

## Keyboard-Focus Popovers

- **`AppKitAnchoredPopover` (via `appKitPopover(isPresented:preferredEdge:content:)`) is the popover for content that must take keyboard focus.** Do not "fix" a non-typing SwiftUI `.popover` with focus retries or key-claim loops; they cannot win against the child-window relationship. Live `NSPopover` host tests are banned (see `AlvearyTests/AGENTS.md`), so this path is verified by hand.
- **Never order a window from `updateNSView`.** SwiftUI runs it inside a Core Animation commit, and ordering there raised `NSViewBridgeErrorException` and crashed. Binds any representable that orders windows, not just this one.

## Keep-Alive Tabs

Rules for adopting `KeepAliveTabContainer`; the container's own doc comment covers what it does and where the `.equatable()` boundary goes.

- **A hidden tab's `onDisappear` no longer runs on a switch.** Cleanup that a deselected tab owes its next activation belongs on `onChange(of:)` of `\.keepAliveTabIsActive`, with `onDisappear` kept for real teardown.
- **A chip row driven by `TabChipButtonStyle` needs `.id(selection)`**, or the highlight sits a selection behind. Both adopters carry it and say why; `KeepAliveTabContainerTests` clicks a real chip and switches back, which is the pass that catches it.

## Status Spinners

- Use `StatusIndicatorSpinner` for fixed-size status spinner slots; do not shrink a `ProgressView` into a dot slot. AppKit surfaces take the `AppKit/AppKitStatusIndicatorSpinner` twin rather than `NSProgressIndicator`, and the two rings stay visually matched (track at 25% alpha, 0.7 arc, same spin period).
- AppKit tool-row loading is the scoped exception: it pulses summary text instead of showing a trailing spinner.
- A spinner's color follows **Status Dot Colors** in `Alveary/Views/AGENTS.md`, which owns that mapping.

## Disabled Cursor

- Use `blockedCursorOverlay(when:)` for disabled SwiftUI controls that should show the macOS blocked cursor. AppKit text editors use `showsDisabledCursor` instead.

## Selectable Rows

`Alveary/Views/AGENTS.md` owns when to reach for `.appSelectableRow(...)`; these are the rules for changing or configuring it.

- **Keep the `.accessibilityAction { action() }` beside the gesture.** The row's press and click both run through a `DragGesture`, which VoiceOver cannot activate on its own.
- Pass a stable row `identity` when rows can be inserted, removed, or reordered, so transient press/pending state cannot leak into recycled `List` rows.
- Keep the background insets at their 10pt defaults unless a surface must compensate for host chrome to hit a measured visual edge.
- **Fade a row through `appSelectionRowBackground(opacity:)`, not an outer `.opacity`.** The fill is published via `listRowBackground`, which SwiftUI hoists out of the row's own render tree, so an outer `.opacity` dims the row's content while leaving a selected row's accent fill fully opaque. Pass the same value to both.

## Split Buttons

- **Use `SplitActionButton` for one primary click target plus a trailing caret menu**, and reuse its chrome rather than hand-rolling an `HStack` divider and menu.
- **The left side runs the selected option; the menu only changes selection.** Adopters outside this scope cite this contract.
- **One accent voice per row.** A split button standing beside a primary action takes `.secondary`; a row where it is the only button may keep `.primary`. `Alveary/Views/DiffViewer/Pane/AGENTS.md` defers here for that.
- Keep SwiftUI `Menu` out of that chrome. The component drives an AppKit `NSMenu` so no second caret, snapshot indicator leak, or height inflation reaches the pill.

## Expandable Headers

- Use `AppHeaderToggle` for compact expand/collapse headers that need the AppKit mouse fallback, and pair `withAnimation(appExpansionAnimation)` with `.appExpansionAnimationOverride(value:)` so the header and the surrounding lazy-list reflow share timing.

## Hover Info Popups

- **Use `AppHoverInfoIcon` / `AppKitHoverInfoButton` for `info.circle` help affordances** rather than plain `.help(...)`, and keep their content unpainted inside the native `NSPopover` chrome so the system owns background, opacity, shadow, and arrow.
- Keep the icon visually stable — muted gray and centered on the adjacent label text — regardless of the parent row's enabled or selected state, since it explains disabled settings too.
- **Rebuild an open tooltip only when its help text changes.** Hover-driven parent updates otherwise collapse the measured wrapped height.
- Preserve the button's accessibility value and help; the hover tooltip does not replace screen-reader help.
