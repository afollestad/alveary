## Onboarding Services

These instructions apply to first-run dependency checks and installer orchestration under `Alveary/Services/Onboarding/`.

- Keep installer execution routed through `ShellRunner` with bounded output, finite timeouts, and null stdin so app-owned installs cannot hang on prompts.
- Use shared detection services for post-install verification. `gh` goes through `GitHubCLIService`; agent CLIs go through `ProviderDetectionService` and `AgentRegistry` metadata.
- Treat an installer command as successful only after a fresh detection pass confirms the dependency is discoverable.
