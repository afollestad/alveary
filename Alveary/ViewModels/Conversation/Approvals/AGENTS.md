## Tool Approvals And Plan Exits

These instructions cover `Alveary/ViewModels/Conversation/Approvals/` — resolving tool approvals, the `ExitPlanMode` confirmation and its denied-plan follow-up, prompt dismissal, and the unresolved-approval registry the waiting dot reads. `Alveary/Services/Agent/Runtime/ToolApproval/AGENTS.md` owns how an approval reaches the provider; the thread status these feed is `Alveary/ViewModels/Conversation/ControllerRegistry/AGENTS.md`.

**Keep a rule here only when the code that would violate it is not the code that documents it.** Most of this scope's behavior now carries its own doc comment: `resolveToolUseApproval`'s prompt precedence, `resumeDeferredToolUse`'s restart-is-not-live rule, `prepareForApprovalResumeIfNeeded`'s flush-before-reset order, `finishLiveDeniedToolApprovalIfNeeded` on allow versus deny, `clearApprovedExitPlanModeApprovalIfNeeded`'s early clear, `handleToolDeferredTokenIfNeeded` on deferral not being a failure, `hydratePendingToolApprovalIfNeeded`'s rehydration, `handleToolApprovalRequested` and `resolveUnresolvedToolApprovalsCompletedByToolResult` on not reopening settled approvals, `supersedePendingToolApprovalAfterPromptAnswer`, the batch-discovery headers in `ConversationViewModel+ToolApprovalBatch.swift`, and the suppression bounds in `ConversationViewModel+Interruption.swift`.

- **Mirror live plan mode.** Runtime `permissionModeChanged` state is the source of truth for live permission decisions; while next-turn settings are pending, fall back to the pre-change permission snapshot, not the staged stored thread mode.
- **Answer the newest prompt approval.** `AskUserQuestion` answers resolve the newest unresolved same-prompt approval record before using stale in-memory state or falling back to normal Q/A sends.
- **`UnresolvedApprovalRegistry` and `SidebarViewModel.hasUnresolvedApproval` are not duplicates.** The registry counts only never-answered rows, because live ones are already blue from the runtime; the fork/Task-move gate additionally counts the transient `.pending`/`.approving` statuses.

### Plan Exits

- **An approved plan exit consumes staged model and effort** — the single exception to "continuations keep the live config" (`Alveary/ViewModels/Conversation/AGENTS.md`): implementation is new work, and the plan overlay offers a reasoning dropdown precisely so the user can implement on a different model.
- **Denial does not restart.** Deny and dismiss leave the change staged; the follow-up is a new visible turn and consumes it there.
- **A custom follow-up stays hidden and busy** until the denied turn reaches a captured terminal boundary or the silent-turn fallback fires, then prepends onto the queue so it sends ahead of older queued messages.
- **Plain Claude revision guidance is transient `ConversationState`, not SwiftData.** Consume it only for eligible normal feedback sends, keep revision-marked queued messages plan-gated and non-steerable, re-arm on queued edit or cancellation rollback, and clear on queued dismissal, provider/session mismatch, plan-mode exit, session handoff, fresh `ExitPlanMode`, or failed approval resolution.
