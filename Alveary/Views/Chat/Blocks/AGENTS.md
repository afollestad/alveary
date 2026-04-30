## Chat Block Primitives

Shared transcript block primitives live here. Narrower scopes:

- `Approvals/AGENTS.md`: `ToolApprovalBlock`.
- `Prompts/AGENTS.md`: `PromptBlock`.
- `Tasks/AGENTS.md`: `TaskListBlock`.
- `Tools/AGENTS.md`: tool rows, groups, details, headers.
- `ChatBlocks+TextBubbles.swift`: user, assistant, streaming, thinking, and error bubble surfaces.
- `ChatBlocks+CenteredNotes.swift`: centered lifecycle notes.

## Bubble Widths

- Bubble widths use `transcriptBubbleMaxWidth`, not hard-coded 720pt.
- `ChatTranscriptView` measures the scroll container, calls `adaptiveTranscriptBubbleMaxWidth(for:)`, then publishes the environment value.
- Text bubbles, prompts, task lists, approvals, streaming/thinking blocks, and errors use the cap.
- Inline tool rows and sub-agent rows intentionally skip bubble chrome and `bubbleMaxWidth`.
- `UserBubble` remains the narrower right-aligned exception with `.frame(maxWidth: 640, alignment: .trailing)`.

## Transcript Typography

- Transcript rows inherit `TranscriptTypography` from `ChatTranscriptView`.
- Use inherited text for body copy; use `transcriptFont(...)` or `transcriptCodeFont()` for explicit variants.
- When a transcript block renders `AppMarkdownText` directly, apply `transcriptMarkdownTypography()` at that surface.
- Do not add raw SwiftUI `.font(...)` in transcript block files; SwiftLint enforces this outside `TranscriptTypography.swift`.
- Keep layout-critical icon sizes as named `TranscriptFontLevel` cases instead of ad hoc font constants.

## Centered Notes

- Use `CenteredTranscriptNote` for subtle lifecycle text: `Interrupted`, plan-mode success, and denied `ExitPlanMode`.
- Render these as centered `info.circle` + text with 24pt vertical padding, not as bubbles or tool rows.
- `TurnInterruptedNote` is only a thin wrapper; new subtle lifecycle rows should use `CenteredTranscriptNote` directly.

## Shared Expansion Controls

- Use `AppHeaderToggle`, `appExpansionAnimation`, and `.appExpansionAnimationOverride(value:)` from `Views/Components`.
- Keep tool-row toggles width-filling, but use the intrinsic-width toggle mode for text-bubble Show more/less so the control does not force the bubble to its width cap.
- Keep the AppKit mouse fallback scoped to the compact control overlay; do not replace it with scroll-view-wide dispatch.
