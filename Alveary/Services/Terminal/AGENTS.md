# Terminal Service Guidance

These rules cover terminal session state under `Alveary/Services/Terminal/`.

- **Prune by launch time.** `TerminalManager` enforces max-session limits by removing the lowest `startedAt` session, not the selected tab or visual edge.
- **Cancel before removal.** Session pruning should go through `closeSession(id:)` so registered running tasks are cancelled and selection repair stays centralized.
