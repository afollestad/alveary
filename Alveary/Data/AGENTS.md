## Data Models

These instructions cover the SwiftData models under `Alveary/Data/`.

- `AgentThread.name` stores the visible thread label, while `AgentThread.hasCustomName` distinguishes a manual rename from the default untitled state. Manual thread rename flows must set `hasCustomName`, and thread auto-naming should only fire while the thread is still effectively untitled (`!hasCustomName && trimmedName == "New thread"`). Conversation auto-titling is a separate rule: the first user message may set `Conversation.title` whenever `customTitle == nil`, even if the thread already has a non-default name. Thread rename cascades to the main conversation's `title` when it still has its default name (`customTitle == nil`); do not add a separate rename affordance for the sole conversation when only one exists.

## Persistence Invariants

These are persistence contracts backed by SwiftData fields. Treat them as hard constraints unless the work explicitly includes a coordinated migration.

- Archived-thread restore uses persisted per-conversation `pendingRestoreContext`, not provider resume. Restoring a thread should regenerate that summary from saved `ConversationEventRecord`s, hydrate it back into `ConversationState.stagedContext` when the conversation view model is recreated, send it only through the existing staged-context path on the next outbound message, and clear the persisted field when the user dismisses it or that send succeeds.
- `Project.remoteName` and `Project.gitRemote` are a paired invariant. Persist and update them together, and have Git/worktree/GitHub flows use the stored `remoteName` instead of rediscovering a remote ad hoc.
