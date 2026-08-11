## App Routing

These instructions cover `Alveary/App/Routing/` — the shared right-pane lane and its destination resolution, Diff Viewer routing, command dispatch, and the notification-borne requests that open a thread or a pull-request pane. The buttons that raise these actions are `Alveary/App/Toolbar/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `RightPaneDestination.resolve` and its purity, `RightPaneContextualTargets`, `DiffViewerRoutingKey`, `DiffViewerRoutingSelection`, `DiffViewerRouteRunner`, `handleThreadOpenRequest`, `handlePullRequestPaneRequest`, and `handleCreatedPullRequest` each carry theirs.

### The Right-Pane Lane

- **One lane, never two.** The layout is a two-column `NavigationSplitView` with a single shared contextual right-pane lane; `RightPaneDestination.resolve` gives any matching contextual target — Skills, MCP, Scheduled, or a pull request — precedence over a requested Diff Viewer. Never mount two right panes, and never switch back to native three-column `NavigationSplitViewVisibility` control on macOS 26.
- **A contextual pane is scoped to the surface that opened it**, which is why `ContentView.rightPaneDestination` builds `RightPaneContextualTargets` from the current selection's origin rather than letting `resolve` check it. `Alveary/Views/PullRequests/AGENTS.md` points here for that scoping.
- **The Diff Viewer request is root-scoped** across project and thread selection changes, as is the lane's width. Repeated show requests are idempotent, so navigation cannot replace the active pane's presentation identity or replay its entrance animation.
    - **Route from one composite keyed task.** Do not re-add routing to `onAppear`, selection/bookmark observers, or a right-pane destination observer; each puts a SwiftData resolve plus a Git switch on the click-to-highlight frame. Observe a mounted conversation's live working directory separately, so a changed worktree on the same thread switches targets without dereferencing a selection token during body evaluation.
    - **Initialize watching separately.** `setWatchingEnabled(_:)` follows `isDiffViewerRendered` through its own observer; it is not part of routing.
- **The lane persists one `AppSettings.rightPaneWidth` for every destination**, written only on resize completion, and must not resize when the destination changes — `RightPaneDestination.feature` names which session a command deactivates, not a width key. `RightPaneWidthPolicy` and the lane's own animation live in `Alveary/Views/Components/Panes/AGENTS.md`.
- **Restore focus only when the lane closes.** `dismissRightPane` passes `restoreFocus` from whether the lane is empty by then, so a pane replaced by the Diff Viewer or by another contextual target must not pull focus back to the control that opened it.

### Command Dispatch

- **One `Task`, one `defer`, one id check.** `handlePendingCommand(_:)` wraps every `AppState.CommandRequest` branch in a single `Task { @MainActor in … }` whose shared `defer` clears `appState.pendingCommand` only while its id still matches the captured `commandID`. Do not clear it inline inside a branch — even for synchronous work — or stale-id semantics diverge and racing commands can nil out a newer one. A new case delegates async work to a helper that takes the captured `commandID` and re-checks it after each `await` before mutating selection or surfacing errors.
- **A voice-model preparation modal can appear mid-command.** Re-check `isModelPreparationModalPresented` after every `await` before changing selection or presenting another modal; the blocking overlay stays mounted until its own Cancel or Continue closes it.

### Requests From The Transcript

- **A link card's pull request opens on the click's own cycle, with no summary** — the pane loads its own detail behind its own spinner. Keep it that way: pre-fetching a summary cost a second identical `fetchDetail`, put a spinner on the card for the wait, and turned a failure into a toast with no pane instead of the pane's own banner.

### The Diff Viewer Back Stack

- **The Git changes footer's pull-request panes get a back stack; nothing else does.** `openLinkedPullRequest(_:preservingDiffViewer: true)` opens the pane over the still-active Diff Viewer request, so its X resolves `.diff` again. The footer's View PR and the post-create open are the only `true` callers; every other opener clears the request, so closing a toolbar- or screen-opened pane does not surface a Diff Viewer the user never asked back for. `Alveary/Views/DiffViewer/Pane/AGENTS.md` points here.
