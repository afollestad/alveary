## Claude Hook Integration

These instructions cover Alveary-owned Claude hook support under `Alveary/Services/Agent/Claude/Hooks/`.

- Keep hook configuration outside user repositories and global Claude settings. Generate session settings in Alveary-owned app support or test temp directories, then pass them with `--settings`.
- Bind hook HTTP listeners only to loopback addresses. Never expose approval hooks on non-local interfaces.
- Fail closed with hook decisions:
    - **Validate every bearer token.** Invalid or missing tokens must return a 2xx JSON `deny` response, not an HTTP error, because Claude treats non-2xx HTTP hook failures as non-blocking.
    - **Deny malformed transport.** Oversized or incomplete raw HTTP hook requests should also return a 2xx PreToolUse `deny` response when possible instead of dropping the connection.
- Treat listener failure as a hard lifecycle reset. Clear the cached port, active launch tokens, permission-mode token mapping, and stored decisions so later Claude launches retry listener startup instead of receiving settings for a dead port.
- Invalidate per-launch hook tokens when the owning Claude process is torn down or exits:
    - **Scope tokens to one launch.** A token belongs to one runtime launch, not to the app-wide listener lifetime.
    - **Release held hook requests.** Any pending approval continuation tied to that token must resume with no decision so teardown/restart cannot leave an HTTP hook request waiting for the full timeout.
- Invalidate the old launch token before recording an approval decision for a resume. A one-shot `allow` / `deny` must only be visible to the new resume launch, not to the deferred launch being torn down.
- Use `PreToolUse` for Alveary approvals. `PermissionRequest` does not fire in Claude `-p` mode because there is no interactive permission dialog.
- `ClaudeHookPolicy.swift` is the source of truth for approval-worthy tool policy. Keep policy changes covered by `ClaudeHookServerTests`.
    - **Generate hook matchers there.** The Claude `PreToolUse` matcher should come from `ClaudeHookPolicy.preToolUseMatcher` so hook registration and defer decisions cannot drift.
    - **Separate potential from current-mode deferral.** `isPotentiallyApprovalControlledTool(...)` / `canRenderToolApproval(...)` answer whether a tool can ever participate in Alveary approval UI, while `shouldDefer(...)` also applies the current Claude permission mode.
    - **Reuse the batch predicates.** Transcript look-ahead and approval-resolution sibling discovery should call `canBatchPotentialApprovalToolCall(...)` / `shouldBatchDeferredToolCall(...)` instead of keeping ad hoc Bash/Write/Edit/MCP tool lists.
- Approval lookups are ordered:
    - **Consume one-shot decisions first.** Decisions are keyed by Claude `session_id` plus `tool_use_id` and must be removed after returning `allow` or `deny`.
    - **Gate reusable approvals by policy.** Stored session approvals and transient batch approvals only apply after `ClaudeHookPolicy.shouldDefer(...)` says the current permission mode is Alveary-controlled for that tool; do not let an old session grant answer hooks that should no-op in the current mode.
    - **Check stored session approvals next.** Session approvals are generic `AgentSessionApprovalRule` rows matched by provider, conversation ID, Claude `session_id`, and a normalized rule payload such as exact Bash command, Bash command group, or exact file path.
    - **Keep Bash group matching conservative.** Only derive a group when the command has an immediate second token that looks like a subcommand and does not contain shell control operators such as `&&`, `;`, `|`, `>`, or `<`; otherwise fall back to exact-only approval. Do not skip over leading flags, because their operands can look like subcommands.
    - **Fall back to defer.** When policy says the tool should be controlled and no reusable approval matched, return `defer` or keep the live hook pending for a user decision.
- Notify the manager from `PreToolUse` instead of waiting for stdout attachments:
    - **Prefer live approval.** When a manager handler is available, emit the `ClaudeDeferredToolRequest`, keep the HTTP request open, and return the user's final `allow` or `deny` decision to the original hook request.
    - **Fall back to defer.** If live approval is unavailable or times out, return `defer`; the notification path should still not depend on Claude's later `hook_deferred_tool` attachment surfacing on stdout.
- `AskUserQuestion` is part of the hook-owned prompt path:
    - **Match it in `PreToolUse`.** If it is not in the matcher, Claude will continue running in `-p` and can emit its own "prompt was dismissed" fallback before Alveary's UI answers anything.
    - **Return `updatedInput` with allow.** An answered `AskUserQuestion` must return the original `questions` array plus an `answers` object; `allow` alone is insufficient.
    - **Consume custom input once.** Clear any stored fallback `updatedInput` alongside the one-shot decision after the hook returns it.
- `ToolApprovalRequest` owns tool-specific user-facing approval metadata:
    - **Keep display copy with the request.** Approval-block labels, concise summaries, supported session scopes, and deferred-composer waiting copy should all derive from `ToolApprovalRequest`, not from duplicate `toolName` switches scattered through the views.
    - **Use `DeferredToolComposerStatusText` for composer overrides.** Deferred tools that need custom composer placeholder/progress copy, such as `AskUserQuestion` or `ExitPlanMode`, should add it there so every composer surface stays in sync.
    - **Use `ToolApprovalPromptCopy` for transcript approval wording.** If a tool needs non-generic approval phrasing, such as `ExitPlanMode` asking whether the user is ready to leave plan mode and treating denial as "keep planning", add that copy on the request instead of branching inside `ToolApprovalBlock`.
- Keep session approvals in Alveary-owned hook storage. Persist `AgentSessionApprovalRule` in the dedicated hook-support SwiftData store under the Claude hooks app-support directory, not in the main conversation transcript store.
- Keep the approval-button selection in the same lifecycle boundary. Persist the last per-session `ToolApprovalSelection` in hook storage so new permission prompts can preselect the user's last choice, and remove it alongside the stored session approval rules for that Claude session.
- Clean up stored approvals with runtime lifecycle:
    - **Discard the just-recorded session approval** if the approval resume fails or resumes without hook settings before Claude can consume it.
    - **Remove all approvals for the old Claude `session_id` in that conversation** when the runtime is destroyed or a resumed stream reports that the conversation is now on a new session ID.

## Plan Mode

- Plan-mode hook handling is asymmetric:
    - **Observe `EnterPlanMode`.** Register it in the matcher so Alveary can see the tool call and rely on later Claude `permissionMode` status updates to sync runtime state, but do not defer or prompt it.
    - **Cache live mode by conversation.** Do not rely only on launch-time hook settings or hook-payload `permission_mode`; update the hook server from streamed `permissionModeChanged` events so `ExitPlanMode` still defers after an in-session `EnterPlanMode`.
    - **Defer `ExitPlanMode` only in live plan mode.** Outside `permissionMode == "plan"`, return no decision so Alveary does not fabricate a plan-exit approval for sessions that are already outside plan mode.
    - **Echo `updatedInput` on allow.** Claude `-p` requires `allow` plus the original `tool_input` for `ExitPlanMode`; returning `allow` alone is insufficient.
