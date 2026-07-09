# Terminal Service Guidance

These rules cover terminal session state and PTY ownership under `Alveary/Services/Terminal/`.

- **Keep sessions metadata-only.** `TerminalSession` tracks tab metadata and status. Do not reintroduce captured output buffers, output trimming, task registration, or `ShellRunner` execution for project actions.
- **Keep PTYs controller-owned.** `TerminalManager` owns a private `[UUID: controller]` map. SwiftUI may mount controller views, but it must not create or replace PTYs during body recomputation, pane hiding, or tab switching.
- **Prune by launch time.** `TerminalManager` enforces max-session limits by removing the lowest `startedAt` session, not the selected tab or visual edge.
- **Terminate through controllers.** Session pruning and closing should go through `closeSession(id:)` so selection repair stays centralized and controller termination always runs. Hiding the pane or switching tabs must not terminate sessions.
- **Preserve SwiftTerm forwarding.** If replacing SwiftTerm's weak `terminalDelegate`, retain a proxy and forward process-critical methods back to `LocalProcessTerminalView` (`send`, `sizeChanged`, title, OSC 7 directory, scroll, and range callbacks). OSC 52 clipboard reads must return `nil`; OSC 52 writes must no-op unless a future user-confirmed policy is added.
- **Capture PID before terminate fallback.** SwiftTerm clears `process.running` during `terminate()`. Fallback termination must capture `process.shellPid` first, call `terminate()`, then use non-blocking `waitpid(..., WNOHANG)` before sending `SIGKILL`.
- **Keep toolbar state project-action-only.** Shell tabs can finish as succeeded or failed and remain visible, but only `.projectAction` sessions should drive toolbar running/completion state.
- **Document the color boundary.** Alveary controls default foreground/background, caret, and ANSI palette colors. Truecolor output and app-defined terminal colors can still choose poor contrast.
