## Claude Hook Integration

These instructions cover Alveary-owned Claude hook support under `Alveary/Services/Agent/Hooks/`.

- Keep hook configuration outside user repositories and global Claude settings. Generate session settings in Alveary-owned app support or test temp directories, then pass them with `--settings`.
- Bind hook HTTP listeners only to loopback addresses. Never expose approval hooks on non-local interfaces.
- Fail closed with hook decisions:
    - **Validate every bearer token.** Invalid or missing tokens must return a 2xx JSON `deny` response, not an HTTP error, because Claude treats non-2xx HTTP hook failures as non-blocking.
    - **Deny malformed transport.** Oversized or incomplete raw HTTP hook requests should also return a 2xx PreToolUse `deny` response when possible instead of dropping the connection.
- Treat listener failure as a hard lifecycle reset. Clear the cached port, active launch tokens, permission-mode token mapping, and stored decisions so later Claude launches retry listener startup instead of receiving settings for a dead port.
- Invalidate per-launch hook tokens when the owning Claude process is torn down or exits. A token is scoped to one runtime launch, not to the app-wide listener lifetime.
- Invalidate the old launch token before recording an approval decision for a resume. A one-shot `allow` / `deny` must only be visible to the new resume launch, not to the deferred launch being torn down.
- Use `PreToolUse` for Alveary approvals. `PermissionRequest` does not fire in Claude `-p` mode because there is no interactive permission dialog.
- `ClaudeHookPolicy.swift` is the source of truth for the allow/defer matrix by permission mode and tool name. Keep policy changes covered by `ClaudeHookServerTests`.
- Approval lookups are ordered:
    - **Consume one-shot decisions first.** Decisions are keyed by Claude `session_id` plus `tool_use_id` and must be removed after returning `allow` or `deny`.
    - **Check stored session approvals next.** Session approvals are generic `AgentSessionApprovalRule` rows matched by provider, conversation ID, Claude `session_id`, and a normalized rule payload such as exact Bash command, Bash command group, or exact file path.
    - **Keep Bash group matching conservative.** Only derive a group when the command has a clear subcommand-like token and does not contain shell control operators such as `&&`, `;`, `|`, `>`, or `<`; otherwise fall back to exact-only approval.
    - **Run policy last.** Only fall back to `ClaudeHookPolicy.shouldDefer(...)` when neither a one-shot decision nor a stored session approval matched.
- Keep session approvals in Alveary-owned hook storage. Persist `AgentSessionApprovalRule` in the dedicated hook-support SwiftData store under the Claude hooks app-support directory, not in the main conversation transcript store.
- Clean up stored approvals with runtime lifecycle:
    - **Discard the just-recorded session approval** if the approval resume fails or resumes without hook settings before Claude can consume it.
    - **Remove all approvals for the old Claude `session_id` in that conversation** when the runtime is destroyed or a resumed stream reports that the conversation is now on a new session ID.
