## Chat Block Primitives

Shared transcript block constants and presentation helpers live here. Narrower scopes:

- `AppKit/AGENTS.md`: AppKit transcript row primitives.
- `Prompts/AGENTS.md`: submitted prompt response parsing and prompt-row rules.
- `Tasks/AGENTS.md`: task presentation ordering and task-row rules.
- `Tools/AGENTS.md`: shared tool summary formatters and tool-row rules.

## Bubble Widths

- Bubble widths use the AppKit row configuration's adaptive cap, not hard-coded 720pt.
- `ChatTranscriptView` measures the scroll container and calls `adaptiveTranscriptBubbleMaxWidth(for:)` before configuring AppKit rows.
- AppKit text bubbles, prompts, task lists, approvals, streaming/thinking blocks, and errors use the cap.
- Inline tool rows and sub-agent rows intentionally skip bubble chrome and `bubbleMaxWidth`.
- User bubbles remain the narrower right-aligned exception capped by `userBubbleMaxWidth`.

## Transcript Typography

- Transcript rows inherit `TranscriptTypography` from `ChatTranscriptView`.
- Use inherited text for body copy; use `transcriptFont(...)` or `transcriptCodeFont()` for explicit variants.
- AppKit transcript rows should bridge `TranscriptTypography` into AppKit labels and markdown renderers directly.
- Do not add raw SwiftUI `.font(...)` in any remaining transcript-adjacent SwiftUI wrappers; SwiftLint enforces this outside `TranscriptTypography.swift`.
- Keep layout-critical icon sizes as named `TranscriptFontLevel` cases instead of ad hoc font constants.

## Transcript Notes

- Subtle lifecycle text like `Interrupted`, plan-mode success, and denied `ExitPlanMode` renders through `AppKitTranscriptNoteView`.
- Render these as text-only transcript notes, not bubbles. Use `TranscriptNoteAlignment`: context compaction and session handoff stay centered, plan-mode and steering notes align with tool rows, and `Interrupted` aligns to the user-bubble trailing edge.

## Shared Expansion Controls

- Use `AppHeaderToggle`, `appExpansionAnimation`, and `.appExpansionAnimationOverride(value:)` from `Views/Components`.
- Keep tool-row toggles width-filling, but use the intrinsic-width toggle mode for text-bubble Show more/less so the control does not force the bubble to its width cap.
- Keep the AppKit mouse fallback scoped to the compact control overlay; do not replace it with scroll-view-wide dispatch.
