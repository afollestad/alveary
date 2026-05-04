## Task List Blocks

Rules for AppKit task-list rows and shared task presentation helpers.

- Keep task checkbox slots fixed at 16x16 so status changes do not reflow rows.
- AppKit in-progress tasks use `NSProgressIndicator` centered inside the same fixed slot.
- Keep progress spinners visually smaller than the fixed status slot; do not stretch them to fill the full 16x16 frame.
- Do not add custom repeat-forever spinner animations; use the platform progress control.
- Keep task ordering and status accessibility labels in shared task presentation helpers so row views and tests stay aligned.
- **Animate AppKit rows visibly.** Reuse rows by task id and apply the new checked/progress visual state before movement.
- Defer row-frame interpolation until after layout computes final sorted positions.
- Restore moving rows to their pre-sort frames before starting `animator()` transitions.
- Keep active animation targets from being overwritten by later layout passes.
