# Terminal Pane Guidance

These rules cover the floating terminal pane in `Alveary/Views/Terminal/`. The pane has a drag handle, a header row (icon + scrolling tab row + new-shell button + close button), and an embedded terminal viewport. Do not add a separate metadata strip above the viewport; tabs own title/status, and interactive project-action shells render their real prompt and injected command in the viewport.

## Session Chips

- Terminal session chips render through the shared `SelectableTabChip` shell. Running project actions use `TabChipStatusIndicator.spinner(.secondary)`; an open interactive shell keeps the same fixed `8×8` slot empty because a live prompt is not inherently busy. Exited shells and completed actions still use success/failure/cancelled dots so status changes never resize the chip.
- Interactive shell chips use the stable label `Shell - <thread>` (or `Shell` without thread context). Keep raw OSC terminal titles as metadata; do not put `user@host:full/path` strings back into the chip. Project-action chips continue to use `<action> - <thread>`.

## Unified Pane Background

- **Drive the pane chrome from a single `panelBackground`.** Only the root `.background(panelBackground)` on the outer VStack sets a fill for pane chrome — do not reintroduce separate `headerBackground`/`bodyBackground` properties or per-region `.background(...)` modifiers, because separately tuned values desynced across themes before this was unified. New per-region chrome must be an overlay, a foreground treatment, or a new global resolving to the same pane color everywhere. Viewport exception: the SwiftTerm viewport owns its own background through `TerminalThemePalette` so terminal colors keep contrast.
- **Keep `panelBackground` noticeably lighter than the inline-code chip fill.** The light-mode chip palette is `NSColor(white: 0.88, ...)` and the pane stays well above it (~0.97), because unselected chips fill with near-transparent `Color.secondary.opacity(0.08)` — a pane near 0.88 makes `@file`-mention chips disappear into the tab surface.

## Tab-Row Edge Dividers

- **Track tab scroll state via `onScrollGeometryChange`, not a GeometryReader + `PreferenceKey` + named `coordinateSpace`.** The ScrollView publishes a `TerminalTabsScrollGeometry` snapshot and the edge dividers gate off it — the GeometryReader pattern did not re-fire on horizontal scroll at all.
    - Publishing the snapshot is necessary but not sufficient: the left divider stayed hidden and the right one stuck visible at end-of-scroll until the gates moved onto the inset-corrected distance that `Alveary/Views/Components/TabChips/AGENTS.md` mandates.
- **Render the dividers as `.overlay(alignment: .leading / .trailing)` on the ScrollView, not as inline HStack siblings** — a sibling with conditional padding re-flows the tab content by 1pt each time the divider appears.
- **Keep the ScrollView greedy (`frame(maxWidth: .infinity)`) when sessions exist, and only render a `Spacer` in the no-sessions branch.** A flexible sibling `Spacer` splits the width and floats the trailing divider mid-pane; the no-sessions branch still needs its Spacer so the close button right-aligns.

- **`testTerminalPaneSessionsOverflow` is the regression guard for this surface.** 8 sessions at 600pt pane width force the overflow state, which pins the trailing-edge divider — the 1pt × 18pt divider is captured in the recorded baseline, so `overlay(alignment: .trailing)` / `onScrollGeometryChange` / `hasTabsBehindTrailingEdge` regressions will fail verification. The leading divider is *not* captured because the test records at scroll distance 0 where `hasTabsBehindLeadingEdge` is false by design; verify the leading divider manually by scrolling forward in the running app.

## Tab Visibility On Selection And Insertion

- **Wrap the tab ScrollView in a `ScrollViewReader` and tag each chip with `.id(session.id)`.** Without an explicit `.id` on each chip `ScrollViewProxy.scrollTo` has no target — the implicit `ForEach` identity is a diffing key, not a scroll-target registration.

- **Scroll on selection via `onChange(of: selectedSession?.id, initial: true)` using `proxy.scrollTo(id)` with a `nil` anchor.** The nil anchor performs the minimum scroll to make the target fully visible, so tapping an already-visible chip does not jump the row — only off-screen chips (e.g. the selected one after opening a dense pane) scroll into view. `initial: true` handles the first render.

- **Scroll on insertion via `onChange(of: sessions.count)` guarded on `newCount > oldCount`**, scrolling to `sessions.last?.id`. Both hooks are needed: a session created with `select: false` never fires the selection `onChange`, so without the count hook passively-created sessions accumulate off-screen. The count-increase guard skips the close path and reselection.
- **Close-adjacent selection on `closeSession` is owned by `TerminalManager`, not the view** — selection is persistent state shared across pane mount cycles, so the view must not re-derive a selection; the scroll-to-selected hook surfaces whichever neighbor the manager picked (mirroring the conversation-tab `selectNeighborIfClosingSelected` pattern).

## Terminal View Hosting

- **Mount controller-owned views only.** `TerminalSessionHostView` should host the `NSView` returned by the session controller. Do not construct `LocalProcessTerminalView` from SwiftUI body code or from tab-chip actions.
- **Inset the viewport at the host boundary.** `TerminalSessionHostingView.contentInsets` reserves terminal breathing room while keeping PTY size calculations tied to the actual SwiftTerm bounds. Paint the host with `TerminalThemePalette` so the inset is visually part of the terminal, not pane chrome.
- **Keep host teardown ownership-aware.** A terminal view can move between representable hosts while SwiftUI dismantles the old host. Clear the previous host before reparenting, and only remove a hosted view when its current superview is that host.
- **Focus only from explicit terminal actions.** The menu/toolbar toggle and new-shell button may request terminal focus through the manager; auto-expanded project-action sessions should not steal first responder.
- **Use fake controllers for snapshots.** Snapshot tests should inject fake controller views so baselines cover pane layout and terminal colors without launching real PTYs.
