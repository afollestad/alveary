## Scheduled Task Services

These instructions cover `Alveary/Services/Scheduled/` — claiming a due occurrence, materializing its workspace, executing the run, and recovering after a crash. The natural-language scheduling tools are nested and own their own rules: `Alveary/Services/Scheduled/HostTools/AGENTS.md`. `Alveary/Data/Scheduled/AGENTS.md` owns the persisted rows, `Alveary/ViewModels/Scheduled/AGENTS.md` the management view models.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Mechanism whose only reader is its own file belongs in a doc comment: `ScheduledTaskSchedulerCoordinator`'s per-definition claim pipelines and why its shutdown deliberately avoids user-stop semantics, `ActiveScheduledTaskExecution`'s retained barrier, why an isolated recovery batch is safe to roll back, and why Run-now recovery ages from its trigger each carry theirs.

### Ownership And Composition

- **Keep scheduling app-owned and provider-neutral.** Provider processes consume immutable run snapshots; they own neither recurrence nor persistence.
- **Validate asynchronously before claiming.** Capture Project and grant directory identities before async work, then revalidate those identities and re-resolve definition revision, state, and occurrence fields before mutating SwiftData.
- **Compose execution through `ScheduledTaskSchedulerCoordinator`.** Same-source worktree creation and overlapping primary/granted roots must keep their separate lock scopes.
- **Use the shared `ConversationControllerRegistry` background lease and outcome stream.** Scheduled execution must never open a second provider subscription.
- `ScheduledTaskSchedulerCoordinator` owns scheduled keep-awake from claimed or recovered run launch through materialization, lock waits, execution, and failure or cancellation.
- **Every scheduled turn's text opens with `DefaultScheduledTaskRunExecutor.scheduledRunPreamble`.** The executor applies it because it is the single path from a run snapshot to a provider turn; a second caller of `startAutomatedScheduledTurn` would otherwise send a run without it.

### Quiescence And User Stop

- **Fence Task archive and delete on coordinator-owned per-run quiescence.** A nonterminal run uses user-stop pending-occurrence clearing; a terminal run only waits for the targeted launch to finish, so historical state is never mutated. Never block unrelated scheduled work with the global idle waiter.
- **Finalize before releasing power.** Executor finalization persists the result and unread state, flushes, and suspends the runtime before the coordinator releases scheduled power. A waiting approval or question retains the lease and runtime.
- **Never use shared-context rollback in coordinator persistence retries.** Flush or reapply the scoped run and conversation mutations instead, so unrelated changes survive; retries retain power throughout.
- **User stop installs a definition fence before awaiting provider cancellation.** It rejects new claims, cancels and quiesces queued same-definition claims, and retains scheduled power until the pending-occurrence clear is durable and the stopped launch has finished.
    - **When user stop finds an inactive fallback `tool_deferred` boundary**, discard only that waiting runtime — preserving its provider session — then supersede every unresolved interaction row, mark any unanswered prompt handled, and emit a durable interruption boundary so run quiescence cannot hang.
- **Coalesce executor stop and cancellation cleanup through the per-run `ActiveScheduledTaskExecution` barrier.** Seal and drain it before clearing automated-run state, so stale runtime teardown cannot reach a later manual turn.

### Recovery And Terminal Proof

- **Treat only `ScheduledTaskRun.hasKnownTerminalStatus` as terminal proof.** Unknown persisted status blocks overlap, Run now, ordinary outbound, and cleanup; unknown trigger or workspace provenance blocks nonterminal execution and resume. Recovery durably interrupts those unsafe nonterminal runs, and known terminal history stays terminal.
- **Recovery interruptions repair provenance rather than inventing it.** Create missing Task and note provenance for unprepared claims, reconstruct only identity-valid prepared-workspace descriptors, and sanitize a changed existing descriptor while preserving ownership-only deletion provenance. Persist terminal state and main-conversation unread routing before badge refresh.
- **Flush preexisting `ModelContext` changes before recovery or termination reconciliation mutates.** If the isolated recovery save fails, roll that batch back and publish neither notifications nor controller flushes.
- **Age automatic claim recovery from the scheduled occurrence**, and Run-now recovery from its explicit trigger time instead.
- **Precompute claimed-run recovery readiness from Sendable immutable snapshots** through the full provider, workspace, and worktree preflight. Recovery's synchronous mutation pass may consume only the resulting safe run IDs.

### Reused-Thread Runs

- **`.existingThread` converts into this mode rather than blocking.** Archiving or deleting the target rewrites the definition (`Alveary/Data/Scheduled/AGENTS.md`), so the paths below are the only ones a former existing-thread schedule can take afterwards.
- **Route a `.reusedThread` run by its relationships, never its destination or snapshot columns**: `run.targetThread != nil` means it posts into the prior run's thread, `run.thread != nil` means it created one, and the to-one `run.thread` may only ever belong to the creating run.
- **Reuse self-heals at claim *and* materialization instead of blocking.** An unhealthy linked thread makes the claim fall back to creating, and a thread lost in the claim→materialize window clears `run.targetThread` and mints a replacement — overwriting the definition's stale link without a revision bump.
- **A targeted reuse run derives its workspace from the thread** (`ScheduledTaskReusedThreadWorkspace`), never from `preparedWorkspace*` columns it never wrote, and **re-asserts the definition's model, effort, and permission mode onto the thread** in the occurrence-note save, because automated spawns supply no overrides and read the thread's stored fields.

### Workspace Materialization

- **Retain a failed private-workspace cleanup's descriptor and prepared marker on the Task shell** so permanent deletion can retry, and clear that provenance only once cleanup succeeds. `Alveary/Data/Scheduled/AGENTS.md` owns which columns make up the retention set.
- **Scheduled Project-worktree materialization uses identity-aware `WorktreeManager` creation and ownership registration.** Preallocate the ownership marker, persist typed cleanup provenance before target creation, update it with target identity and proven branch ownership, and clear it only in the same save that promotes the final Task workspace descriptor.
    - **Before removing a worktree, durably refresh the branch's exact HEAD OID** and persist the ownership-retirement fence before deletion. Restore retryable ownership only when Git proves that exact ref remains; legacy cleanup without an OID must leave the branch behind. Never bless or remove a same-path replacement.
- **Preserve persisted Project and grant path strings literally** through preflight and immutable run snapshots. Canonicalization validates them; it must not rewrite a symlink replacement into an apparently valid root before comparison.

### Deadlines And Occurrence Coalescing

- **`ScheduledTaskLifecycleCoordinator` activates only after launch cleanup, session and orphan cleanup, and provider refresh.** Its deadline must rearm after `.scheduledTasksChanged`, scheduler claim completion, wake reconciliation, and system clock or time-zone changes.
- **Hold a due `pendingOccurrenceAt` while any nonterminal or unknown-status run exists for that definition**, but keep considering `nextOccurrenceAt` so newer cadence work can coalesce.
- **Publish claim, recovery-interruption, and terminal changes through `.scheduledTasksChanged`** so management state and deadline reconciliation share one durable boundary.
- **Scheduled transcript notes are display-only provenance.** Exclude them from provider context, restore summaries, and forks.
