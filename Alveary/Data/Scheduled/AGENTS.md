## Scheduled Task Data

These instructions cover `Alveary/Data/Scheduled/` — the scheduled task definition, its immutable run snapshots, recurrence, and the natural-language proposal a conversation confirms. `Alveary/Services/Scheduled/AGENTS.md` owns execution, recovery, and quiescence, `Alveary/Services/Scheduled/HostTools/AGENTS.md` the `alveary_host` tools that write these rows; `Alveary/ViewModels/Scheduled/AGENTS.md` owns the management view models. Whether a thread may be a schedule's target is `AgentThread+ScheduledTarget.swift` in `Alveary/Data/Threads/`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `ScheduledTaskProposalPlacement`'s inherit-on-`nil` default, `ScheduledTaskProposalWorkspace`'s deliberately absent run location and its grant-replacement semantics, and `ScheduledTaskProposalReceipt`'s legacy-nil fields each carry theirs.

### Definitions, Runs, And Proposals

- **Keep recurrence structured.** `ScheduledTask` persists flat recurrence fields plus a pinned IANA timezone; use its `recurrence` bridge, never RRULE text.
- **Snapshot before execution.** `ScheduledTaskRun.init(snapshotting:...)` makes revision, prompt, provider settings, project path, grants, occurrence identity, and claimed directory identities durable across edits and definition deletion. Missing or malformed identity provenance fails closed for execution and recovery.
- **Decode persisted run state exactly in safety gates.** Use `decodedStatus` and `hasKnownTerminalStatus`; the `status` bridge's `.failure` fallback is presentation compatibility, not proof an unknown raw value is terminal.
    - Unknown nonterminal status, trigger, or workspace provenance blocks execution and resume and is interrupted during recovery, while known terminal status stays authoritative history.
- **Scope crash recovery for terminal interactions.** Set `ScheduledTaskRun.requiresFinalizationRecovery` in the same save as executor-owned terminal state, and clear it durably only after interaction cleanup and verified runtime suspension. Startup may supersede terminal-run approvals and questions only while the marker is set.
- **Preserve history with nullification.** Project deletion nullifies schedules, schedule deletion nullifies runs, and Task-thread deletion nullifies run provenance; existing Project-thread and conversation cascades stay unchanged.
- **`targetThread` is the user's pick; `reusedThread` is service-owned.** Keep a reuse schedule's created thread out of `targetThread`, whose inverse still refuses the mutations that would silently retarget a live definition. `Alveary/Services/Scheduled/AGENTS.md` owns how runs route around a detached link.
- **A schedule never pins or holds its target.** Archiving or deleting that thread converts the definition to `.reusedThread`, inheriting the lost thread's workspace (`Alveary/Services/ScheduledTaskTargetDetachment.swift`); project deletion also pauses it. `Alveary/ViewModels/Sidebar/AGENTS.md` owns the calling commits.
- **`ScheduledTask.threadSection` is a creation-time seed, not live membership** — editing it never moves an already-created thread, and only a projectless new-thread destination may carry it; `ScheduledTaskMutationService` clears it otherwise.
- **Mutate future work only.** Definition mutations are revision-checked; pause, resume, and edit clear `pendingOccurrenceAt` and recompute `nextOccurrenceAt` strictly after the action time. Never rewrite an active run snapshot. Project deletion pauses and detaches definitions without changing run Task workspaces.
- **Keep natural-language proposals noncanonical.** `ScheduledTaskProposal` is one pending, conversation-owned confirmation snapshot: it cascades with its source conversation, nullifies its trusted Project, fails closed on unknown payload versions and actions, and revision-checks the definition again at confirmation.
    - **A `nil` or nonpositive `enqueueOrdinal` is a pre-field row and sorts first**, by date and ID. Keep that branch when touching FIFO ordering; `Alveary/Services/Scheduled/HostTools/AGENTS.md` owns assigning the positive values.

### Workspace Cleanup Provenance

- **Retain failed owned-workspace cleanup provenance** — original source path and directory identity, worktree path, branch, and ownership-record identity — until marker-verified filesystem *and* Git cleanup both complete.
- **The private-workspace cleanup-failure retention set is the descriptor plus `preparedWorkspaceRoot`, `preparedOwnershipStrategyRawValue`, and `preparedWorkspaceMarkerID`.** `Alveary/Services/Scheduled/AGENTS.md` owns when they are retained and cleared.
- **A workspace-less scheduled Task shell is deletion-safe only when terminal.** Reject deletion when prepared-workspace or pending-cleanup fields are ambiguous or incomplete. A sanitized shell may derive an ownership-only cleanup descriptor from validated prepared metadata, but must not re-expose changed Project or grant roots.
