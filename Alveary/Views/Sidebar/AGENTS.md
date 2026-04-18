## Sidebar Interaction Patterns

These instructions cover sidebar-specific view code under `Alveary/Views/Sidebar/`.

> **READ FIRST — Focus and keyboard rules are centralized.** Before touching `@FocusState`, `.onKeyPress`, or `.keyboardShortcut` anywhere in this folder, consult the **Focus And Keyboard Coordination** section in `Alveary/Views/AGENTS.md`. It owns the sidebar's focus-restoration hook, the cross-surface release to the composer, modifier-shortcut placement, and `.onKeyPress` conflict rules. The sidebar-specific bullets below (row behaviors, traversal order, arrow-key semantics) stack on top of that parent contract — they are not a replacement for it.

- Thread rename is inline (Finder-style `TextField` swap in `SidebarThreadRow`), not a modal sheet. The row tracks an `editingThreadID` binding.
- `SidebarThreadRow` renders on a single line. Do not reintroduce a branch or worktree subtitle; threads with and without a worktree are meant to share a uniform row height.
- Thread names are rendered via the shared `AppMarkdownInlineLabel`, which keeps plain rows and rows with inline-code chips at a uniform height. `testSidebarThreadRowChipAndPlainShareHeight` locks this in — if you rework the label, keep the chip row's height matching a plain row.
- Deleting the selected sidebar thread should keep focus within the same project when possible: prefer the previous visible thread in the project list, otherwise the next visible thread, and only fall back to the project row when no visible threads remain.
- Sidebar keyboard navigation traverses items in a flat order: Skills → MCP → each project row with its visible threads interleaved when expanded → next project. The traversal is built by `buildNavigableItems()` and driven by `navigateVertically()` in `SidebarView+KeyboardNavigation.swift`.
- Horizontal arrows intentionally reuse that vertical path in some cases: left-arrow behaves like up-arrow for `Skills`, `MCP`, thread rows, and already-collapsed project rows, while right-arrow behaves like down-arrow for `Skills`, `MCP`, thread rows, and already-expanded project rows. Collapsed and expanded project rows still use left and right to collapse or expand first.
- When adding new top-level sidebar sections or changing expansion behavior, update the keyboard-navigation functions and their tests together.
