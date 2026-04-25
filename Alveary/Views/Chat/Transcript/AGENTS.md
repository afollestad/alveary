## Chat Transcript

Transcript-shell rules live here. Narrower scopes:

- `Scrolling/AGENTS.md`: follow-mode, pending scrolls, watchdogs.
- `Links/AGENTS.md`: markdown and file-mention link resolution.

> **READ FIRST:** Focus and keyboard rules are centralized in `Alveary/Views/AGENTS.md`.

## Tool Approval Plumbing

- `ChatView+Transcript+ToolApproval.swift` keeps transcript approval actions thin.
- It should pass through the current approval request, persisted status, and approval callbacks.
- Prompt/approval interaction policy lives in `Alveary/Views/Chat/AGENTS.md`.
- Approval surface rendering lives in `../Blocks/Approvals/AGENTS.md`.
