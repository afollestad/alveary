## View Models

These instructions apply to files under `Alveary/ViewModels/`.

- Keep view models as coordination layers: route UI intent, own observers/watchers, and delegate service-backed state to focused collaborators when state becomes shared or long-running.
- Put feature-specific view-model rules in the narrowest subfolder guidance, such as `Alveary/ViewModels/DiffViewer/AGENTS.md`.
