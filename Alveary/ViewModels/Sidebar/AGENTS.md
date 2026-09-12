## Sidebar View Models

These instructions apply to files under `Alveary/ViewModels/Sidebar/`. `ArchivedThreadsViewModel` is not here — see `Alveary/ViewModels/AGENTS.md`.

### Thread Lifecycle

- Thread removal routes through `SidebarViewModel` lifecycle methods so runtime teardown, notification cleanup, provider-native session retirement (archive on archive, delete on delete — see `Alveary/Services/Agent/AGENTS.md`), worktree cleanup, and branch cleanup stay coordinated. Views needing to delete a thread — including project-trust denial flows — receive a focused delete closure instead of calling `ModelContext.delete(_:)` on `AgentThread`.
- **Thread creation and archiving live in `ThreadLifecycleService`**, not in `SidebarViewModel`. The view model is per-window, so app-scoped callers (the `alveary_host` thread tools) cannot route through it; both build the service over the shared `mainContext` and it holds no state. Add a new caller by using the service, never by copying the body — `SidebarViewModel` keeps only the UI half (ordering refresh, selection routing, diagnostics presentation) and delegates. Drafts, restore, delete, and fork stay view-side; a draft is the service's `isDraft` seed plus the view model's caching and materialization.
    - **Route around an externally archived selection.** An archive from outside the window posts `.threadLifecycleChanged` with the thread already archived; `SidebarView.handleThreadLifecycleChanged` reuses the same replacement-selection path the window's own archive uses. Restores post it too, so check `SidebarViewModel.archivedThread(id:)` before acting.
- Sidebar order normalization lives in `SidebarOrderNormalization`, parameterized by `ModelContext`, because a lifecycle mutation with no window still has to renumber pinned and regular orders inside the same save.
- Thread pinning is `ThreadLifecycleService.setThreadPinned(threadID:isPinned:)` for the same reason; `SidebarViewModel` delegates and owns only the `refreshThreadOrder` that follows. Its `ThreadPinOutcome` distinguishes "already in that state" from "a pinned project absorbs it", which the sidebar treats alike but the host tool must not.
- Keep draft deletion atomic with its lifecycle boundary:
  - Commit the SwiftData removal before the first `await` so concurrent New Thread requests cannot reuse or materialize the deleted row.
  - Remove conversation attachment directories only after runtime teardown has been attempted, including teardown-failure paths.
  - Before a targeted mutation that may call `ModelContext.rollback()`, synchronously save pre-existing shared-context changes — a target failure must not discard unrelated pending work.
- Creation uses one provisional draft across project, Tasks, and custom-section placement. Keep its conversation and composer state when switching destination; commit workspace changes before releasing a replaced private workspace off the main actor. Materialization freezes the workspace, including hidden initial setup.
- **Run owned-workspace removal and identity probes off the main actor** — through the `nonisolated` cleanup half in `SidebarViewModel+TaskWorkspaceCleanup.swift`, never a direct main-actor `taskWorkspaceOwnershipService` removal call: a workspace can hold a full checkout, and the recursive delete beachballs the app. The fence-bound pending-scheduled path is the documented exception.

### Scheduled Attachments

- A Task row with pending scheduled-worktree cleanup is the user-visible retry owner: complete that cleanup before committing permanent deletion; never leave retry-only provenance on a threadless run.
  Reject overlapping cleanup attempts for the same run while its durable branch-retirement fence may represent an in-flight deletion. Once branch ownership is durably retired, a later retry may clear that provenance only after identity-aware removal proves the persisted worktree and ownership sidecar absent; leave the unprovable branch behind.
- Archiving or permanently deleting a Task linked to a scheduled run must quiesce that coordinator launch before the SwiftData commit: stop nonterminal runs, but only wait for already-terminal runs so runtime finalization and notification routing finish without mutating historical schedule state.
- **A schedule targeting a thread never blocks that thread's lifecycle — only a live run does.** Archive, thread delete, and project delete take `requireThreadLifecycleIsUnblocked`, then call `ScheduledTaskTargetDetachment.detachTargets(of:)` in their own save, while the row still carries the workspace survivors inherit.
    - **A review proposal blocks on the same terms**: pending blocks nothing, a submit already inside GitHub blocks both actions, from `PullRequestReviewSubmissionActivity` — whose doc comment owns why it is fed by notification. Add a new blocking reason to `requireThreadLifecycleIsUnblocked` and to `threadCleanupBlockedReason`, never to one alone: the second is the tooltip on controls the first refuses, and the hover pill reaches the mutation without passing `requestArchive`/`requestDelete`.
    - Publish through `postScheduledTasksDetached` only after that save commits.
    - `scheduledTaskAttachmentError(for:)` survives for the two mutations that would silently retarget a live definition: the Task-to-Project drop (`validateTaskProjectAccess`) and main-conversation deletion (`ThreadDetailConversationDeletion`).
    - Project deletion detaches only its cascade-deleted `threadSnapshots`; `detachedTaskThreadIDs` survive the delete, so schedules targeting those keep their thread.

### Ordering And Drag

- Keep Task threads and unplaced source threads in the Task drag domain; `supportsIndependentSidebarPlacement` defines this independently of execution mode. Project pinning absorbs children of either mode.
- Commit drops into Tasks through `SidebarSectionService.moveThread(threadID:to:)` so pin, project, and custom-section membership clear together. A drop into the owning project only unpins; it retains project placement.
- `SidebarViewModel.moveTaskIntoProject(_:projectID:)` owns the sidebar's Task-to-Project drop. It changes placement and grants folder access; it never changes mode:
    - **Set `project` and grant every member folder.** Preserve the Task's primary workspace, ownership, and mode; only placement and additional access change.
    - **Suspend, never destroy.** A running process was launched without the new root, so suspend it; the working directory is unchanged, so the provider resumes its session next turn. `kill`/`destroyRuntime` would discard the session record and lose the conversation.
    - **Refuse rather than half-apply.** Drafts, archived threads, multi-conversation Tasks, scheduled-attached Tasks, busy or waiting runtimes, unresolved approvals, an unchanged placement with all folders already granted, and unavailable source folders all reject before any mutation.
    - **Clear the pin.** Placement in a project always drops a standalone pin — leaving it renders the Task as a project child *and* its own `Pinned` row, so the drop looks like a no-op. A pinned destination additionally absorbs the child. Pinning afterwards still promotes it back out.
    - **Trust does not apply.** Provider trust is a working-directory concept; granted roots are never auto-trusted.
- Edit grants only for a fully idle, single-conversation thread without schedule attachments. Persist canonical roots, reconfigure a tracked idle runtime, keep suspended runtimes asleep, and roll back persistence and runtime configuration together on failure.
