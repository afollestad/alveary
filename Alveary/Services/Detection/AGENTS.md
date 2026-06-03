## Agent And Provider Detection

These instructions cover agent and provider metadata under `Alveary/Services/Detection/`.

- `AgentRegistry` is the single source of truth for shared agent metadata. When adding or changing an agent, update `Alveary/Services/Detection/DefaultAgentRegistry.swift` and derive provider install guidance, detection metadata, skills directories, and MCP integration metadata from that shared entry instead of introducing feature-local agent lists.
- Runtime-ready provider status and model options are exposed through `AgentCLIKit.AgentProviderDiscoveryService`; `AgentRegistry` remains Alveary's static metadata source for install guidance, extra args, skills, and MCP integration.
- Finder-launched apps have a minimal `PATH`; provider executable detection should try `which`, then a timed login-shell `command -v`, then explicit fallback directories.
