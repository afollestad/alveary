## Task List Blocks

Rules for `TaskListBlock`.

- Keep task checkbox slots fixed at 16x16 so status changes do not reflow rows.
- In-progress tasks use a standalone `ProgressView` scaled to match the checkbox glyph.
- Do not use a custom repeat-forever SwiftUI spinner; keep animation in AppKit's progress-indicator layer.
