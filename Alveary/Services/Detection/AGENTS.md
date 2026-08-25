## Agent And Provider Detection

These instructions cover agent and provider metadata under `Alveary/Services/Detection/`.

- `AgentRegistry` is the single source of truth for shared agent metadata. When adding or changing an agent, update `Alveary/Services/Detection/DefaultAgentRegistry.swift` and derive provider install guidance, detection metadata, skills directories, and MCP integration metadata from that shared entry instead of introducing feature-local agent lists.
- Runtime-ready provider status and model options are exposed through `AgentCLIKit.AgentProviderDiscoveryService`; `AgentRegistry` remains Alveary's static metadata source for install guidance, sign-in commands, extra args, skills, and MCP integration.
    - **A provider with no sign-in command gets no Sign In affordance.** `AgentDefinition.signInCommand` is optional and every caller gates on it, so an agent that authenticates some other way must not be given a placeholder command.
- Finder-launched apps have a minimal `PATH`; provider executable detection should try `which`, then a timed login-shell `command -v`, then explicit fallback directories.
