## Onboarding Services

These instructions apply to first-run dependency checks and installer orchestration under `Alveary/Services/Onboarding/`.

- Keep installer execution routed through `ShellRunner` with bounded output, finite timeouts, and null stdin so app-owned installs cannot hang on prompts.
- Use shared detection services for post-install verification. `gh` goes through `GitHubCLIService`; agent CLIs go through `ProviderDetectionService` and `AgentRegistry` metadata.
- Treat an installer command as successful only after a fresh detection pass confirms the dependency is discoverable.
- Detect Command Line Tools with `xcode-select -p`, then run git at the developer directory it reports. Never spawn `/usr/bin/git` to probe: on a machine without CLT that shim pops a system-modal install dialog. Do not hardcode the CommandLineTools path either — full Xcode ships git too.
- Install `gh` with Homebrew only when `brew` already resolves; otherwise download the official release binary into `~/.local/bin`. Never bootstrap Homebrew: its installer needs `sudo`, which the null-stdin rule above guarantees will abort.
- Run piped installer commands under `set -o pipefail`. Without it a failed `curl … | sh` exits 0, so an offline install reports success and then fails detection for no stated reason.
- Give required dependencies manual-install guidance (`OnboardingDependency.manualInstallGuidance`). The modal cannot be dismissed and `gh` cannot be optional, so a machine the in-app installer cannot serve still needs a way forward.
