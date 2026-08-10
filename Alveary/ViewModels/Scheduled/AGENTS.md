## Scheduled Task View Models

These instructions apply to files under `Alveary/ViewModels/Scheduled/`. `Alveary/Services/Scheduled/AGENTS.md` owns the coordinator and store; `Alveary/Views/Scheduled/AGENTS.md` owns the screens.

- Scheduled management observes persisted scheduler change notifications. Keep Run-now actions pending until the coordinator reports claim resolution; elapsed-time delays are not a synchronization boundary.
- Editor drafts and transcript panes follow the contextual-pane session contract in `Alveary/ViewModels/AGENTS.md` — cache by stable target, guard async completions on the session generation.
- Rules for running a schedule live elsewhere: background leases and the blocks a nonterminal run imposes on outbound work are in `Alveary/ViewModels/Conversation/AGENTS.md`, and quiescing a run attached to a Task being archived or deleted is in `Alveary/ViewModels/Sidebar/AGENTS.md`.
