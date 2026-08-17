import Foundation
import SwiftData

extension DefaultScheduledTaskRunMaterializer {
    /// Materializes a `.reusedThread` run into the thread a prior run created.
    ///
    /// Modelled on `materializeExistingTarget` with three deliberate differences: no pin
    /// requirement (reuse threads are never pinned); the workspace derives from the thread
    /// instead of re-preparing a project-local one; and an unusable thread returns `nil` — the
    /// self-heal — instead of throwing, so `materialize` detaches it and creates a replacement
    /// rather than failing an unattended run. A changed grant configuration still throws: minting
    /// a thread under unvalidated grants would widen the authorization boundary silently.
    ///
    /// Re-asserts the snapshot's model, effort, and permission mode onto the thread in the same
    /// save as the occurrence note, because automated spawns supply no overrides and read the
    /// thread's stored fields — without this, editing the definition's agent settings would never
    /// take effect. Plan and speed mode are deliberately untouched: the definition models
    /// neither, so the thread's own values stay authoritative for them.
    func materializeReusedTarget(
        runID: PersistentIdentifier,
        snapshot: ScheduledTaskRunSnapshot
    ) throws -> ScheduledTaskRunMaterialization? {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        guard let thread = run.targetThread,
              thread.archivedAt == nil,
              !thread.isDraft,
              !thread.hasPendingScheduledTaskWorktreeCleanup,
              let targetConversationID = snapshot.targetConversationID,
              let conversation = thread.conversations.first(where: {
                  $0.isMain && $0.id == targetConversationID
              }),
              conversation.provider == snapshot.providerID,
              !ScheduledTaskExistingTargetReadiness.hasBlockingPersistedInteraction(in: conversation),
              let workspace = ScheduledTaskReusedThreadWorkspace.descriptor(thread: thread, run: run) else {
            return nil
        }
        guard let workspaceIdentities = snapshot.workspaceIdentities,
              workspaceIdentities.matchesConfiguration(
                  workspaceKind: snapshot.workspaceKind,
                  projectPath: snapshot.projectPath,
                  grantedRootPaths: snapshot.grantedRoots
              ) else {
            throw ScheduledTaskRunMaterializationError.workspaceRootsChanged
        }
        let capturedSettings = (model: thread.model, effort: thread.effort, permissionMode: thread.permissionMode)
        thread.model = snapshot.model
        thread.effort = snapshot.effort
        thread.permissionMode = snapshot.permissionMode
        let note = makeScheduledTaskNote(run: run, snapshot: snapshot, conversation: conversation)
        modelContext.insert(note)
        do {
            try saveChanges(modelContext)
        } catch {
            modelContext.delete(note)
            (thread.model, thread.effort, thread.permissionMode) = capturedSettings
            run.status = .claimed
            run.preparationStartedAt = nil
            throw ScheduledTaskRunMaterializationError.provenancePersistenceFailed(error)
        }
        return ScheduledTaskRunMaterialization(
            runID: runID,
            threadID: thread.persistentModelID,
            conversationID: conversation.id,
            prompt: snapshot.prompt,
            workspace: workspace
        )
    }
}
