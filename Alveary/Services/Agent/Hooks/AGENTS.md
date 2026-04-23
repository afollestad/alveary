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
- Consume stored approval decisions once. Decisions are keyed by Claude `session_id` plus `tool_use_id` and must be removed after returning `allow` or `deny`.
- Discard stored approval decisions if approval resume fails or resumes without hook settings before Claude can consume the hook. Retrying from the UI should create a fresh decision.
