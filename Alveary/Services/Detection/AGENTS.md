## Agent And Provider Detection

These instructions cover agent and provider metadata under `Alveary/Services/Detection/`.

- `AgentRegistry` is the single source of truth for shared agent metadata. When adding or changing an agent, update `Alveary/Services/Detection/DefaultAgentRegistry.swift` and derive provider install guidance, detection metadata, skills directories, and MCP integration metadata from that shared entry instead of introducing feature-local agent lists.
