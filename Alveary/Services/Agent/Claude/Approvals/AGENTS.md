## Claude Approvals

These instructions cover Alveary-owned approval code under `Alveary/Services/Agent/Claude/Approvals/`.

- Keep only durable session approval persistence, approval-selection persistence, and approval UI display policy here.
- Provider hook transport, generated hook settings, live/fallback hook decisions, Claude session paths, restored approval transcript inspection, and provider-level approval policy belong in `AgentCLIKit`.
- `DefaultClaudeApprovalPersistenceStore` intentionally keeps using the historical `Application Support/Alveary/ClaudeHooks` store directory so existing reusable approvals continue to load. Despite the path name, durable approvals inside it are provider-scoped and may belong to Claude or Codex.
- Use `ClaudeApprovalDisplayPolicy` for Alveary UI approval rendering and approval-batch decisions. It may wrap `AgentCLIKit.ClaudeHookPolicy`, but it must not duplicate provider tool lists or MCP mutating-tool detection.
- Native read-only tool calls may be groupable transcript rows even when their escaping `tool_approval` rows render approval prompts.
- Keep `ToolApprovalRequest` as the owner for user-facing approval copy, summaries, supported session scopes, and deferred-composer status text.
