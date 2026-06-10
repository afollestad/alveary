# Terminal Pane Guidance

These rules cover the floating terminal pane in `Alveary/Views/Terminal/`. The pane has three stacked regions — drag handle, header row (icon + scrolling tab row + close button), body ScrollView with the selected session's output.

## Session Chips

- Terminal session chips render through the shared `SelectableTabChip` shell. Keep `.running` on `TabChipStatusIndicator.spinner(.secondary)` in the same fixed `8×8` status slot as terminal success/failure dots so a session starting or finishing does not change chip height.

## Unified Pane Background

- **Drive all three regions from a single `panelBackground`.** The drag handle, the header row, and the body ScrollView must all share the same background — do not reintroduce separate `headerBackground` or `bodyBackground` computed properties, and do not add per-region `.background(...)` modifiers.
    - **Why:** Users explicitly asked for visual uniformity across the regions so the three palettes cannot drift apart in light or dark themes. Earlier iterations had three separately-tuned values, which desynced every time one of them was adjusted.
    - **How to apply:** Only the root `.background(panelBackground)` on the outer VStack should set a fill. New backgrounds inside the VStack (e.g. a per-region accent) must be replaced with an overlay, a foreground-driven treatment, or a new global that still resolves to the same pane color in every region.

- **Keep `panelBackground` noticeably lighter than the inline-code chip fill.** In light mode the chip palette is `NSColor(white: 0.88, ...)`; the pane background must stay well above that (currently ~0.97) so `@file`-mention chips inside unselected tab chips stay visible.
    - **Why:** Unselected chips fill with `Color.secondary.opacity(0.08)` — nearly transparent — so the tab's rendered color is roughly the pane background. If the pane drops near the chip's 0.88 gray, the mention chip disappears into the tab surface. This is exactly the regression that triggered the unify-and-lighten change.

## Tab-Row Edge Dividers

- **Track tab scroll state via `onScrollGeometryChange`, not a GeometryReader + `PreferenceKey` + named `coordinateSpace`.** The ScrollView publishes a `TerminalTabsScrollGeometry` snapshot (content width, container width, content offset), and the leading / trailing edge dividers gate off that snapshot.
    - **Why:** The GeometryReader-in-a-background-of-the-content pattern (proxy frame in a named coordinate space) did not re-fire on horizontal scroll — the left divider stayed hidden and the right divider stayed visible at end-of-scroll. `onScrollGeometryChange` reports fresh geometry on every scroll frame.

- **Render the dividers as `.overlay(alignment: .leading / .trailing)` on the ScrollView, not as inline HStack siblings with conditional padding.** Overlays do not affect the ScrollView's own layout, so the dividers appear / disappear without shifting the tab content by 1pt.
    - **Why:** A sibling divider with conditional leading padding on the ScrollView would re-flow the scroll content each time the divider appeared, producing a visible jump the first time the user scrolled forward.

- **Keep the ScrollView greedy (`frame(maxWidth: .infinity)`) when sessions exist, and only render a `Spacer` in the no-sessions branch.** The close button right-aligns because the ScrollView consumes the remaining width, not because a sibling Spacer pushes it.
    - **Why:** With both the ScrollView and a sibling `Spacer(minLength: 0)` flexible, SwiftUI split the available width between them and the trailing-edge divider floated mid-pane instead of hugging the close button. The no-sessions branch still needs a Spacer so the close button right-aligns when no tabs are rendered.

- **`testTerminalPaneSessionsOverflow` is the regression guard for this surface.** 8 sessions at 600pt pane width force the overflow state, which pins the trailing-edge divider — the 1pt × 18pt divider is captured in the recorded baseline, so `overlay(alignment: .trailing)` / `onScrollGeometryChange` / `hasTabsBehindTrailingEdge` regressions will fail verification. The leading divider is *not* captured because the test records at `contentOffset == 0` where `hasTabsBehindLeadingEdge` is false by design; verify the leading divider manually by scrolling forward in the running app.

## Tab Visibility On Selection And Insertion

- **Wrap the tab ScrollView in a `ScrollViewReader` and tag each chip with `.id(session.id)`.** Without an explicit `.id` on each chip `ScrollViewProxy.scrollTo` has no target — the implicit `ForEach` identity is a diffing key, not a scroll-target registration.

- **Scroll on selection via `onChange(of: selectedSession?.id, initial: true)` using `proxy.scrollTo(id)` with a `nil` anchor.** The nil anchor performs the minimum scroll to make the target fully visible, so tapping an already-visible chip does not jump the row — only off-screen chips (e.g. the selected one after opening a dense pane) scroll into view. `initial: true` handles the first render.

- **Scroll on insertion via `onChange(of: sessions.count)` guarded on `newCount > oldCount`.** `TerminalManager.createSession` appends to the end, so a newly-added session may not become the selected session but should still surface — scroll to `sessions.last?.id`. The count-increase guard skips the close-session path (count decreases) and reselection of an existing session.
    - **Why both hooks are needed:** a new session with `select: true` fires the selection `onChange`, but a new session with `select: false` does not — its ID isn't the selected ID. Without the count-increase hook, passively-created sessions would silently accumulate off-screen whenever the row was already scrolled.

- **Close-adjacent selection on `closeSession` is owned by `TerminalManager`, not the view.** When the currently-selected session is closed, `TerminalManager` picks the session that now sits at the closing session's former index (the next neighbor), falling back to `sessions.last` when the last tab was closed — mirroring the conversation-tab `selectNeighborIfClosingSelected` pattern. The view relies on this: the scroll-to-selected hook will surface whichever neighbor the manager picked, so do not re-derive a new selection from within the pane.
    - **Why in the manager:** selection is persistent state shared across pane mount cycles. Losing selection during the close-then-remount window would reset to an unrelated session; keeping the decision in the manager ensures the next time the pane mounts, the chosen neighbor is already selected.
