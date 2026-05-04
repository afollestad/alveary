## Chat Transcript

Transcript-shell rules live here. Narrower scopes:

- `Scrolling/AGENTS.md`: follow-mode, pending scrolls, watchdogs.
- `Links/AGENTS.md`: markdown and file-mention link resolution.

> **READ FIRST:** Focus and keyboard rules are centralized in `Alveary/Views/AGENTS.md`.

## Tool Approval Plumbing

- Tool approval rendering and actions are AppKit-owned through `Scrolling/ChatView+Transcript+AppKitBridge.swift`.
- Prompt/approval interaction policy lives in `Alveary/Views/Chat/AGENTS.md`.
- Native approval surface rendering lives in `../Blocks/AppKit/AGENTS.md`.

## Typography

- `ChatTranscriptView` publishes `TranscriptTypography`, applies the root body font, and bridges it into `AppMarkdownTypography`.
- New transcript text should inherit that root font unless it intentionally uses `transcriptFont(...)` or `transcriptCodeFont()`.
