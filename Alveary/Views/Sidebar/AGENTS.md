## Sidebar Interaction Patterns

These instructions cover sidebar-specific view code under `Alveary/Views/Sidebar/`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.onKeyPress`, or `.keyboardShortcut` anywhere in this folder, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`. It owns the sidebar's focus-restoration hook, the cross-surface release to the composer, modifier-shortcut placement, and `.onKeyPress` conflict rules. The sidebar-specific bullets below (row behaviors, traversal order, arrow-key semantics) stack on top of that parent contract — they are not a replacement for it.

- `SidebarProjectRow`'s leading icon `Button` is load-bearing for click-to-expand:
    - **Action:** Toggles expansion, never project activation. `onToggleExpanded` must remain the sole action; project activation lives on the sibling content affordance plus the row's transparent background tap target so dead space inside the selected-row chrome still opens the project.
    - **Default icon:** Render the folder glyph when the icon is not hovered.
    - **Hovered icon:** Transition the icon to `chevron.right` for collapsed projects and `chevron.down` for expanded projects while the pointer is over the icon button.
    - **Toggle feedback:** Keep the icon in the hovered chevron state after clicks and switch it to the opposite chevron as `isExpanded` changes; return to the folder glyph when hover ends.
    - **Hit region:** Keep the fixed 16×16 frame paired with `.contentShape(Rectangle())` so the folder button stays easy to hit even though the glyph is smaller than the nominal box. A `.plain` `Button` without `.contentShape` hit-tests against the SF Symbol's intrinsic outline, which makes clicks near the frame edges miss the toggle.
    - **Accessibility:** Provide an explicit `.accessibilityLabel` that reflects the current toggle action (`Expand <project>` / `Collapse <project>`). Without it, VoiceOver falls back to the SF Symbol's raw name (`"folder, button"`).
- `SidebarProjectRow`'s trailing new-thread button mirrors row emphasis:
    - **Selected visibility:** Keep the button visible and hit-testable while the project row is selected.
    - **Hover visibility:** For unselected rows, keep the existing row-hover fade-in behavior and hide the button again when hover ends.
    - **Control hover:** Row hover makes the trailing button visible, but only pointer hover over the button itself should show the circular button background.
    - **Column alignment:** Keep `SidebarSectionHeaderRow`'s add-project button center aligned with this row's new-thread button center.
- Sidebar project rows are single-line. Do not reintroduce branch/path/local subtitles under the project name; expanded thread lists and the project settings surface already carry that metadata.
- Sidebar project rows share `SidebarRowMetrics.topLevelAndThreadContentHeight` with thread rows. Do not add extra vertical padding around project row content; selected and hovered project rows should match thread row height.
- Pinned threads render as a top-level sidebar group directly under `MCP` and above `Projects`:
    - **Show the conditional header.** Render the `Pinned` header only when pinned threads exist, and keep it visually matched with the `Projects` header styling and insets.
    - **Keep project ownership.** Pinning changes only sidebar placement. The `AgentThread.project` relationship still owns cleanup, diff actions, project deletion, and restore behavior.
    - **Hide from project lists.** Pinned active threads must not also render under their expanded project.
    - **Use existing activity ordering.** Pinned rows sort with `AgentThreadOrdering`, so outbound or turn-ended activity updates their order just like project thread rows.
    - **Keep top-level alignment.** Pinned rows have no leading icon or reserved project-thread spacer; their title starts at the top-level row inset.
- Thread rename is inline (Finder-style `TextField` swap in `SidebarThreadRow`), not a modal sheet. The row tracks an `editingThreadID` binding.
- `SidebarThreadRow` renders on a single line. Do not reintroduce a branch or worktree subtitle; threads with and without a worktree are meant to share a uniform row height.
- `SidebarThreadRow` status indicator layout:
    - **Align trailing:** Keep the trailing status slot size-locked and aligned with the center of the project/header trailing action buttons.
    - **Fill width:** Keep the row framed to `maxWidth: .infinity` so the trailing dot reaches the same action column as project-row icon buttons.
    - **Preserve title alignment:** Keep the invisible leading slot so thread titles stay aligned with project names.
    - **Match busy sizing:** `.busy` uses a spinner in the same fixed frame as the colored dot (`8×8` today) so status changes do not change row height or nudge the label vertically.
    - **Show worktrees inline:** Threads with `useWorktree` show a rotated branch glyph before the status/cleanup frame with a 6pt explicit gap. Hovering the glyph uses the shared hover tooltip to show the worktree path, or `Worktree path not created yet` before setup creates one.
    - **Reserve trailing controls:** Keep the title gap, worktree glyph, and status/cleanup frame in a fixed-width trailing cluster so long thread names ellipsize before the glyph instead of overlapping or shifting it.
- `SidebarThreadRow` cleanup action overlays the status dot:
    - **Keep hidden by default:** Show the archive/delete icon button only while the row is hovered or confirmation is armed.
    - **Control hover:** Row hover makes the cleanup button visible, but only pointer hover over the button itself should show the circular button background. The selected-row background and the shared row-hover background are separate states.
    - **Anchor confirmation right:** Keep the red `Confirm` pill icon-height.
      It expands left from the status column, and the whole rounded pill is the hit target.
      If confirmation times out after hover leaves, collapse the pill width to zero without a fade.
    - **Pause confirmation deliberately:** Keep the confirmation timeout paused while the pointer is over the pill or the mouse is pressed on it.
      If press ends outside the pill and hover is gone, resume the timeout.
    - **Reserve spacing deliberately:** Keep an 8pt title gap before the plain status dot.
      Keep the same 8pt title gap when the archive/delete cleanup icon is visible so hover does not change title truncation.
- Thread names are rendered via the shared `AppMarkdownInlineLabel`, which keeps plain rows and rows with inline-code or `@mention` chips at a uniform height. `testSidebarThreadRowChipAndPlainShareHeight` locks this in for inline-code chips — if you rework the label, keep every chip row's height matching a plain row. Mention-chip rendering is snapshot-locked separately by `testSidebarThreadRowMentionTitleRendersChip`.
- Thread rows render chip colors through `AppMarkdownInlineLabel`, which always uses the `.standard` palette — chip fill stays uniform across selection transitions. The uniform-color contract is the product decision; do not reintroduce selection-aware chip swapping here by reaching past the label into `AppMarkdownInlineCodeChip(style: ...)`.
- The thread row "Rename..." context menu entry and VoiceOver rotor action are both gated on `editingThreadID == nil`, matching the keyboard path in `renameThreadID(for:editingThreadID:)`. Swapping `editingThreadID` from one row to another mid-edit left the target row stuck in editing state without an input field — the simultaneous unmount of the in-flight row's TextField and mount of the target row's within a single SwiftUI update pass didn't converge. Force users to finish the in-flight rename (Enter / Escape / click away) before starting a new one.
- Deleting the selected sidebar thread should keep focus within the same project when possible: prefer the previous visible thread in the project list, otherwise the next visible thread, and only fall back to the project row when no visible threads remain.
- Sidebar keyboard navigation traverses items in a flat order: Skills → MCP → pinned threads → each project row with its visible unpinned threads interleaved when expanded → next project. The traversal is built by `buildNavigableItems()` and driven by `navigateVertically()` in `SidebarView+KeyboardNavigation.swift`.
- Horizontal arrows intentionally reuse that vertical path in some cases: left-arrow behaves like up-arrow for `Skills`, `MCP`, thread rows, and already-collapsed project rows, while right-arrow behaves like down-arrow for `Skills`, `MCP`, thread rows, and already-expanded project rows. Collapsed and expanded project rows still use left and right to collapse or expand first.
- When adding new top-level sidebar sections or changing expansion behavior, update the keyboard-navigation functions and their tests together.
- Visible sidebar thread lists should come from `SidebarViewModel.activeThreads(for:)`, not from filtering `project.threads` in SwiftUI render code. Fetching live, unarchived rows through the view model avoids SwiftData traps from stale relationship entries during `List`/`ForEach` refreshes.
