## Scheduled Task Services

### Ownership And Composition

- Keep scheduling app-owned and provider-neutral. Provider processes consume immutable run snapshots; they do not own recurrence or persistence.
- Validate asynchronously before claiming, capture Project/grant directory identities before async work, then revalidate those identities and re-resolve definition revision, state, and occurrence fields before mutating SwiftData.
- Use `ScheduledTaskSchedulerCoordinator` for execution composition. Same-source worktree creation and overlapping primary/granted roots must retain their separate lock scopes.
- Use the shared `ConversationControllerRegistry` background lease and outcome stream. Scheduled execution must not create a second provider subscription.
- `ScheduledTaskSchedulerCoordinator` owns scheduled keep-awake from claimed/recovered run launch through materialization, lock waits, execution, and failure or cancellation.

### Quiescence And User Stop

- Use coordinator-owned per-run quiescence for Task archive/delete fences. Nonterminal runs use user-stop pending-occurrence clearing; terminal runs only wait for the targeted launch to finish so historical state is not mutated. Never block unrelated scheduled work with the global idle waiter.
- Executor finalization persists the result and unread state, flushes, and suspends the runtime before the coordinator releases scheduled power. Waiting approvals/questions retain the lease and runtime.
- Coordinator persistence retries retain power and must never use shared-context rollback; flush or reapply scoped run/conversation mutations without discarding unrelated changes.
- User stop installs a definition fence before awaiting provider cancellation, rejects new claims, cancels and quiesces queued same-definition claims, and retains scheduled power until the pending occurrence clear is durable and the stopped launch finishes.
- Coalesce executor stop/cancellation cleanup through the per-run `ActiveScheduledTaskExecution` barrier. Seal and drain it before clearing automated-run state so stale runtime teardown cannot reach a later manual turn.
- If user stop finds an inactive fallback `tool_deferred` boundary, discard only that waiting runtime while preserving its provider session, supersede every unresolved interaction row, mark any unanswered prompt handled, and emit a durable interruption boundary so run quiescence cannot hang.

### Recovery And Terminal Proof

- Recovery interruptions create missing Task/note provenance for unprepared claims, reconstruct only identity-valid prepared-workspace descriptors, and sanitize changed existing descriptors while preserving ownership-only deletion provenance. Persist terminal state and main-conversation unread routing before badge refresh.
- Recovery and termination reconciliation must flush preexisting `ModelContext` changes before mutating. If the isolated recovery save fails, roll back that batch and do not publish notifications or flush controllers.
- Treat only `ScheduledTaskRun.hasKnownTerminalStatus` as terminal proof. Unknown persisted status blocks overlap, Run now, ordinary outbound, and cleanup; unknown trigger/workspace provenance blocks nonterminal execution or resume. Recovery durably interrupts those unsafe nonterminal runs, while known terminal history remains terminal.
- Age automatic claim recovery from the scheduled occurrence; age Run-now recovery from its explicit trigger time because it may consume an older occurrence.

### Workspace Materialization

- If private-workspace cleanup fails during materialization, retain its descriptor and prepared marker on the Task shell so permanent deletion can retry; clear that provenance only after cleanup succeeds.
- Scheduled Project-worktree materialization must use identity-aware `WorktreeManager` creation and ownership registration. Preallocate the ownership marker, persist typed cleanup provenance before target creation, update it with target identity and proven branch ownership, and clear it only in the same save that promotes the final Task workspace descriptor. Before worktree removal, durably refresh the associated branch's exact HEAD OID and persist the ownership-retirement fence before deletion; restore retryable ownership only when Git proves that exact ref remains. Legacy cleanup without an OID must leave the branch behind. Never bless or remove a same-path replacement.
- Preserve persisted Project and grant path strings literally through preflight and immutable run snapshots. Canonicalization validates them; it must not rewrite a symlink replacement into an apparently valid root before comparison.

### Deadlines And Occurrence Coalescing

- `ScheduledTaskLifecycleCoordinator` activates only after launch cleanup, session/orphan cleanup, and provider refresh. Its deadline must rearm after `.scheduledTasksChanged`, scheduler claim completion, wake reconciliation, and system clock/time-zone changes.
- While a definition has any nonterminal or unknown-status run, hold its due `pendingOccurrenceAt` until that run finishes, but continue considering `nextOccurrenceAt` so newer cadence work can coalesce. Publish claim, recovery-interruption, and terminal changes through `.scheduledTasksChanged` so management state and deadline reconciliation share one durable boundary.
- Precompute claimed-run recovery readiness from Sendable immutable snapshots through the full provider/workspace/worktree preflight. Recovery's synchronous mutation pass must only consume the resulting safe run IDs.
- Scheduled transcript notes are display-only provenance. Exclude them from provider context, restore summaries, and forks.

### Natural-Language Proposals

- Scheduling enrolls on the shared `alveary_host` server; `Services/HostMCP/AGENTS.md` owns the generic handler contract (strict validation, trusted identity, source-first reads, confirmation only where irreversible) and how a feature enrolls. The rules below are what scheduling adds on top.
- Natural-language scheduling tools may list definitions, apply a reversible action, or persist a pending proposal. Bind provider settings, permissions, Project paths, and grants from trusted host state. Never expose prompts from list results.
- **Scheduling's reads take no arguments.** `list_scheduled_tasks`, `list_projects`, and `list_threads` are the whole read surface; an argument-taking read could be steered into probing. The two lookups hand user data to the provider — Project paths, and conversation-derived thread names — so the server instructions gate each to the ask that needs it, and `list_threads` omits ineligible threads entirely rather than reporting them as unavailable.
- **`resolveSource` adds automated-run gating** to the shared resolution: a thread with a nonterminal scheduled run, or a blocking run attachment, cannot schedule.
- **Placement is user-confirmed, never self-authorized.** `destination`, `target_thread_id`, and `workspace` are optional on create and inside an edit's `changes`; omitting them inherits the calling thread's or the definition's own. `ScheduledTaskHostToolRequestParser+Placement.swift` owns shape, `ScheduledTaskHostToolService+Placement.swift` owns what host state allows.
    - **A named Project must already be registered** — an unknown path is refused, never registered on the fly. `granted_roots` replaces the inherited set and, matching the editor pane, may combine with `project_path` and add folders; the pending message and confirmation pane disclose every grant.
    - **Store grant paths symlink-safely.** A selected root that is still inherited keeps its inherited literal; a new root must be an absolute path to an existing folder and is stored canonically resolved, so a symlink spelling cannot show the user one folder while granting another.
    - **Run location stays host-bound.** A `localCheckout` schedule would mutate the user's real working copy unattended, so no schema field reaches `workspaceStrategy`; neither do provider, model, effort, or permission mode.
    - **A drafted resolution stores the draft's Project, not the definition's.** The confirmation pane compares `ScheduledTaskProposal.project` against the draft's `projectPath` and refuses a mismatch as a vanished Project, so an edit moving a task to another Project must carry that Project through.
    - **Canonicalize placement into the dedup payload.** Two proposals differing only in where the task runs would otherwise collapse into one replayed receipt.
    - **Disclose it in the pending message.** `placementSummary` names the destination or workspace the request asked for, including a target thread that confirming will pin — the pane shows all of it, but a plain-text-fallback provider has only this sentence to relay.
- **Confirmation is required only where the change is not reversible.** `ScheduledTaskHostToolService.appliesWithoutConfirmation` is the single list: pause, resume, and run-now apply immediately and return `status: "applied"`, because each is revision-checked, undoable from the Scheduled screen, and changes no definition content. Create and edit change content and delete is irreversible, so all three still open a proposal and return `status: "pending_confirmation"`. The confirmation-path resolvers run first on the immediate path too, so revision conflicts and invalid state transitions still reject before anything mutates.
- **Outcome markers name the definition they produced and echo the target's title** so a confirmed create — whose id exists nowhere in the tool payload — can still open its task, and a plain-text-fallback provider's widget can still name it. Deletion records no definition, because there is nothing left to open. Immediate actions record a confirmed marker too, keyed by their deduplication key; without it a fallback provider's widget could never read as applied.
- **Immediate actions still record a receipt.** It is the retry ledger: an exact retry replays the recorded result instead of acting twice, which is what stops a repeated run-now from launching a second run. Run-now additionally passes the deduplication key as its occurrence idempotency key.
- Keep one FIFO proposal per source conversation, assign persisted positive enqueue ordinals for tied timestamps, and scope exact-retry deduplication by process token, request ID, and canonical typed-payload hash. Persist each `pending_confirmation` receipt before returning it; consuming or rejecting the proposal must not let a delayed exact retry open another one. Create/edit/pause/resume/delete confirmation consumes the proposal with the definition mutation; Run now carries the proposal ID into occurrence identity so a cleanup retry cannot launch duplicate work.
- A follow-up request that revises the same target supersedes the unconfirmed proposal instead of being refused; the superseded one is rejected so its transcript widget never leaves two live confirmations for one task.
- Proposal outcomes reach the transcript as `host_tool_outcome` marker rows written by `ScheduledTaskProposalOutcomeRecorder` **in their own save, immediately after** the save that consumed or deleted the proposal. Do not fold the marker into that transaction: those paths roll back on failure, and rolling back a context holding a freshly inserted record next to a deleted model traps inside SwiftData. Failing between the two saves leaves the widget unresolved, never wrongly resolved.
- Receipts echo the target task's `title` so a widget can name the task after its proposal row is gone.
