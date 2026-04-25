## Tool Approval Blocks

Rules for `ToolApprovalBlock`.

- Render `.toolApproval` and `.toolApprovalBatch` as assistant-side approval surfaces.
- Use standard assistant bubble chrome via `bubbleBackground(maxWidth:)`.
- Use the compact tool-row header anatomy for the lock/title header.
- Put the tool family in the title: `Approve Bash command?`, `Approve Bash commands?`, or `Approve writing to files?`.
- Keep summaries and buttons under the header text column, not under the leading icon.
- Chip Bash command summaries as compact code chips; keep non-Bash summaries subtle plain text.
- Keep vertical gaps even between title, summaries, and actions.
- Show concise summaries only; do not dump full tool input JSON.
- Read title subjects and button labels from `ToolApprovalRequest`, not view-local `toolName` switches.
- Batch approvals show one surface with one summary per included tool because one click resolves the live hook batch.
- Intersect batch session scopes; never offer a batch menu item that a sibling request cannot receive.
- Only the live approval is interactive. Superseded rows render past-tense `Superseded`.
- Disable approval controls while the same conversation has an unanswered `AskUserQuestion`.
- Supported tools use an Approve split button plus Deny.
    - The left side runs the selected approval mode.
    - The caret switches between `Approve once` and supported session modes.
    - Unsupported tools show one-shot Approve/Deny only.
- Bash may expose `Approve exactly` and `Approve group` when the command has a clear group and is not compound shell.
- File edits stay exact-path only plus generic `Approve for session`.
- Once resolution starts, hide the opposite action and show a disabled past-tense state.
    - `.approving` / `.approved`: show `Approved`.
    - `.denying` / `.denied`: show `Denied`.
    - Session-approved states show only the resolved session title.
    - Nil/non-pending status keeps actions disabled so users cannot submit twice.
- Preserve pending action width with opacity-hidden, non-interactive placeholders.
- Only visible actions get matched-geometry IDs; placeholders must not be animation endpoints.
- In `ViewThatFits`, enable matched geometry only for the primary horizontal candidate.
