## Chat Block Primitives

Shared transcript block primitives live here. Narrower scopes:

- `Approvals/AGENTS.md`: `ToolApprovalBlock`.
- `Prompts/AGENTS.md`: `PromptBlock`.
- `Tasks/AGENTS.md`: `TaskListBlock`.
- `Tools/AGENTS.md`: tool rows, groups, details, headers.

## Bubble Widths

- Bubble widths use `transcriptBubbleMaxWidth`, not hard-coded 720pt.
- `ChatTranscriptView` measures the scroll container, calls `adaptiveTranscriptBubbleMaxWidth(for:)`, then publishes the environment value.
- Text bubbles, prompts, task lists, approvals, streaming/thinking blocks, and errors use the cap.
- Inline tool rows and sub-agent rows intentionally skip bubble chrome and `bubbleMaxWidth`.
- `UserBubble` remains the narrower right-aligned exception with `.frame(maxWidth: 640, alignment: .trailing)`.

## Centered Notes

- Use `CenteredTranscriptNote` for subtle lifecycle text: `Interrupted`, plan-mode success, and denied `ExitPlanMode`.
- Render these as centered `info.circle` + text with 24pt vertical padding, not as bubbles or tool rows.
- `TurnInterruptedNote` is only a thin wrapper; new subtle lifecycle rows should use `CenteredTranscriptNote` directly.

## Shared Animation

- `toolExpansionAnimation` is the single expand/collapse easing. Tune it here.
- Use both animation scopes for expanding tool-like rows:
    - `.toolAnimationOverride(value:)` scopes row subtree changes.
    - `withAnimation(toolExpansionAnimation) { ... }` scopes the surrounding `LazyVStack` reflow.
- Do not remove either piece; one animates the row internals, the other animates neighboring transcript positions.

## Compact Mouse Targets

- `TranscriptHeaderToggle` owns compact expand/collapse controls used by tool rows and long assistant bubbles.
- Keep its SwiftUI `Button` as the primary path for keyboard and accessibility activation.
- `TranscriptMouseTarget` is a bounded AppKit fallback for mouse delivery after animated lazy-list height changes.
- Scope the fallback to the tiny control overlay, and skip it when the SwiftUI button already activated.
- Keep tool-row toggles width-filling, but use the intrinsic-width toggle mode for assistant-bubble Show more/less so the control does not force the bubble to its width cap.
