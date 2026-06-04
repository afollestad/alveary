## Claude Approvals

These instructions cover Alveary-owned approval code under `Alveary/Services/Agent/Claude/Approvals/`.

- Keep only durable session approval persistence, approval-selection persistence, and approval UI display policy here.
- Provider hook transport, generated hook settings, live/fallback hook decisions, Claude session paths, restored approval transcript inspection, and provider-level approval policy belong in `AgentCLIKit`.
- `DefaultClaudeApprovalPersistenceStore` intentionally keeps using the historical `Application Support/Alveary/ClaudeHooks` store directory so existing reusable approvals continue to load after the hook transport moved to `AgentCLIKit`.
- Use `ClaudeApprovalDisplayPolicy` for Alveary UI grouping/rendering decisions. It may wrap `AgentCLIKit.ClaudeHookPolicy`, but it must not duplicate provider tool lists or MCP mutating-tool detection.
- Keep `ToolApprovalRequest` as the owner for user-facing approval copy, summaries, supported session scopes, and deferred-composer status text.
