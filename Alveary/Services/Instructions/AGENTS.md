## Global Agent Instructions

These instructions cover the shared instructions services under `Alveary/Services/Instructions/`.

- The shared instructions file is `~/.agents/AGENTS.md`; per-agent paths (`AgentDefinition.instructionsPath`) come from `AgentRegistry`, never feature-local lists.
- Migration is opt-in and non-destructive. `link` must back the original up beside itself as `<filename>.backup` before removing anything, and must create the shared file first so the symlink never dangles.
- `link` never touches `linked` or `linkedElsewhere` paths; foreign symlinks are the user's own scheme.
- Tilde expansion uses the injected home directory, not `NSHomeDirectory()`, so tests can run against a temp dir.
