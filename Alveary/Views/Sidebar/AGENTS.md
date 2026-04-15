## Sidebar Interaction Patterns

These instructions cover sidebar-specific view code under `Alveary/Views/Sidebar/`.

- Thread rename is inline (Finder-style `TextField` swap in `SidebarThreadRow`), not a modal sheet. The row tracks an `editingThreadID` binding.
- Deleting the selected sidebar thread should keep focus within the same project when possible: prefer the previous visible thread in the project list, otherwise the next visible thread, and only fall back to the project row when no visible threads remain.
- Sidebar keyboard navigation traverses items in a flat order: Skills → MCP → each project row with its visible threads interleaved when expanded → next project. The traversal is built by `buildNavigableItems()` and driven by `navigateVertically()` in `SidebarView+KeyboardNavigation.swift`.
- Horizontal arrows intentionally reuse that vertical path in some cases: left-arrow behaves like up-arrow for `Skills`, `MCP`, thread rows, and already-collapsed project rows, while right-arrow behaves like down-arrow for `Skills`, `MCP`, thread rows, and already-expanded project rows. Collapsed and expanded project rows still use left and right to collapse or expand first.
- When adding new top-level sidebar sections or changing expansion behavior, update the keyboard-navigation functions and their tests together.
