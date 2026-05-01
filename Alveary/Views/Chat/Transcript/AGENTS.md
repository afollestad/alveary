## Chat Transcript

Transcript-shell rules live here. Narrower scopes:

- `Scrolling/AGENTS.md`: follow-mode, pending scrolls, watchdogs.
- `Links/AGENTS.md`: markdown and file-mention link resolution.

> **READ FIRST:** Focus and keyboard rules are centralized in `Alveary/Views/AGENTS.md`.

## Tool Approval Plumbing

- `ChatView+Transcript+ToolApproval.swift` keeps transcript approval actions thin.
- It should pass through the current approval request, persisted status, and approval callbacks.
- Prompt/approval interaction policy lives in `Alveary/Views/Chat/AGENTS.md`.
- Native approval surface rendering lives in `../Blocks/AppKit/AGENTS.md`; legacy SwiftUI approval rules live in `../Blocks/Approvals/AGENTS.md`.

## Typography

- `ChatTranscriptView` publishes `TranscriptTypography`, applies the root body font, and bridges it into `AppMarkdownTypography`.
- New transcript text should inherit that root font unless it intentionally uses `transcriptFont(...)` or `transcriptCodeFont()`.
