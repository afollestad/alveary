## Task List Blocks

Rules for AppKit task-list rows and shared task presentation helpers.

- Keep task checkbox slots fixed at 16x16 so status changes do not reflow rows.
- AppKit in-progress tasks use `AppKitStatusIndicatorSpinner` centered inside the same fixed slot.
- Keep progress spinners at 12x12 with a 1.5pt stroke so the ring visually matches checkbox glyph size inside the 16x16 slot.
- Do not swap task rows back to `NSProgressIndicator`; transcript AppKit spinner behavior is centralized in `Views/Components/AppKit/AppKitStatusIndicatorSpinner.swift`.
- Keep task ordering and status accessibility labels in shared task presentation helpers so row views and tests stay aligned.
- **Animate AppKit rows visibly.** Reuse rows by task id and apply the new checked/progress visual state before movement.
- Defer row-frame interpolation until after layout computes final sorted positions.
- Restore moving rows to their pre-sort frames before starting `animator()` transitions.
- Keep active animation targets from being overwritten by later layout passes.
