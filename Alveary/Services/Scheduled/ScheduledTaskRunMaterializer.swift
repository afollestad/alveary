import Foundation
import SwiftData

@MainActor
final class DefaultScheduledTaskRunMaterializer: ScheduledTaskRunMaterializing {
    typealias FailureNotification = @MainActor (_ message: String, _ conversationID: String) -> Void

    let modelContext: ModelContext
    let worktreeManager: any WorktreeManager
    let workspaceOwnershipService: any TaskWorkspaceOwnershipService
    private let locale: Locale
    let now: () -> Date
    let saveChanges: @MainActor (ModelContext) throws -> Void
    private let failureNotification: FailureNotification
    let provenancePersistenceAttempts: Int

    init(
        modelContext: ModelContext,
        worktreeManager: any WorktreeManager,
        workspaceOwnershipService: any TaskWorkspaceOwnershipService,
        locale: Locale = .autoupdatingCurrent,
        now: @escaping () -> Date = Date.init,
        saveChanges: @escaping @MainActor (ModelContext) throws -> Void = { try $0.save() },
        failureNotification: @escaping FailureNotification = { _, _ in },
        provenancePersistenceAttempts: Int = 3
    ) {
        self.modelContext = modelContext
        self.worktreeManager = worktreeManager
        self.workspaceOwnershipService = workspaceOwnershipService
        self.locale = locale
        self.now = now
        self.saveChanges = saveChanges
        self.failureNotification = failureNotification
        self.provenancePersistenceAttempts = max(1, provenancePersistenceAttempts)
    }

    func materialize(runID: PersistentIdentifier) async throws -> ScheduledTaskRunMaterialization {
        let snapshot: ScheduledTaskRunSnapshot
        do {
            snapshot = try transitionToPreparing(runID: runID)
        } catch let snapshotError {
            if (snapshotError as? ScheduledTaskRunMaterializationError)?.isInvalidPersistedSnapshot == true {
                try persistInvalidSnapshotFailure(runID: runID, error: snapshotError)
            }
            throw snapshotError
        }
        if snapshot.destination == .existingThread {
            return try materializeExistingTarget(runID: runID, snapshot: snapshot)
        }
        try persistTaskShellWithRetry(runID: runID, snapshot: snapshot)

        let preparedWorkspace = try await prepareWorkspaceOrPersistFailure(
            runID: runID,
            snapshot: snapshot
        )

        do {
            try Task.checkCancellation()
            guard let liveRun = modelContext.resolveScheduledTaskRun(id: runID),
                  liveRun.status == .preparing,
                  liveRun.thread != nil else {
                throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
            }

            let result = try persistPreparedTaskThread(
                for: liveRun,
                snapshot: snapshot,
                preparedWorkspace: preparedWorkspace
            )
            return result
        } catch {
            try await handlePreparedWorkspaceFailure(
                error,
                preparedWorkspace: preparedWorkspace,
                runID: runID,
                wasCancelled: error is CancellationError
            )
        }
    }
}

extension DefaultScheduledTaskRunMaterializer {
    func materializeExistingTarget(
        runID: PersistentIdentifier,
        snapshot: ScheduledTaskRunSnapshot
    ) throws -> ScheduledTaskRunMaterialization {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing,
              let thread = run.targetThread,
              thread.isPinned,
              thread.archivedAt == nil,
              !thread.isDraft,
              !thread.hasPendingScheduledTaskWorktreeCleanup,
              let targetConversationID = snapshot.targetConversationID,
              let conversation = thread.conversations.first(where: {
                  $0.isMain && $0.id == targetConversationID
              }),
              !ScheduledTaskExistingTargetReadiness.hasBlockingPersistedInteraction(in: conversation) else {
            throw ScheduledTaskRunMaterializationError.existingTargetUnavailable
        }
        guard let workspaceIdentities = snapshot.workspaceIdentities,
              workspaceIdentities.matchesConfiguration(
                  workspaceKind: snapshot.workspaceKind,
                  projectPath: snapshot.projectPath,
                  grantedRootPaths: snapshot.grantedRoots
              ),
              let projectPath = snapshot.projectPath else {
            throw ScheduledTaskRunMaterializationError.workspaceRootsChanged
        }
        let workspace = try prepareProjectLocalWorkspace(
            projectPath: projectPath,
            grantedRoots: snapshot.grantedRoots,
            workspaceIdentities: workspaceIdentities
        ).descriptor
        let note = makeScheduledTaskNote(run: run, snapshot: snapshot, conversation: conversation)
        modelContext.insert(note)
        do {
            try saveChanges(modelContext)
        } catch {
            modelContext.delete(note)
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

private extension ScheduledTaskRunMaterializationError {
    var isInvalidPersistedSnapshot: Bool {
        switch self {
        case .invalidDestination, .invalidTimeZone, .invalidWorkspaceConfiguration:
            return true
        default:
            return false
        }
    }
}

extension DefaultScheduledTaskRunMaterializer {
    func persistTaskShellWithRetry(
        runID: PersistentIdentifier,
        snapshot: ScheduledTaskRunSnapshot
    ) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing,
              run.thread == nil else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }

        let thread = makeTaskThread(run: run, snapshot: snapshot, preparedWorkspace: nil)
        let conversation = Conversation(
            provider: snapshot.providerID,
            isMain: true,
            displayOrder: 0,
            thread: thread
        )
        let note = makeScheduledTaskNote(run: run, snapshot: snapshot, conversation: conversation)
        thread.conversations = [conversation]
        conversation.events = [note]
        run.thread = thread
        modelContext.insert(thread)
        modelContext.insert(conversation)
        modelContext.insert(note)

        var persistenceError: Error?
        for _ in 0..<provenancePersistenceAttempts {
            do {
                try saveChanges(modelContext)
                return
            } catch {
                persistenceError = error
            }
        }

        resetFailedTaskInsertion(run: run, thread: thread, conversation: conversation, note: note)
        run.status = .claimed
        run.preparationStartedAt = nil
        throw ScheduledTaskRunMaterializationError.provenancePersistenceFailed(
            persistenceError ?? ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        )
    }

    func persistPreparedTaskThread(
        for run: ScheduledTaskRun,
        snapshot: ScheduledTaskRunSnapshot,
        preparedWorkspace: PreparedScheduledTaskWorkspace
    ) throws -> ScheduledTaskRunMaterialization {
        let workspace = preparedWorkspace.descriptor
        guard let thread = run.thread,
              let conversation = thread.conversations.first(where: \.isMain) else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        applyPreparedWorkspaceMetadata(preparedWorkspace, run: run, thread: thread)
        try retainWorkspaceCleanupProvenanceIfNeeded(preparedWorkspace, run: run)
        run.clearPendingWorktreeCleanup()
        try saveChanges(modelContext)

        return ScheduledTaskRunMaterialization(
            runID: run.persistentModelID,
            threadID: thread.persistentModelID,
            conversationID: conversation.id,
            prompt: snapshot.prompt,
            workspace: workspace
        )
    }

    func retainWorkspaceCleanupProvenanceIfNeeded(
        _ preparedWorkspace: PreparedScheduledTaskWorkspace,
        run: ScheduledTaskRun
    ) throws {
        let workspace = preparedWorkspace.descriptor
        guard workspace.ownershipStrategy == .projectWorktreeOwned else {
            run.workspaceCleanupProvenance = nil
            return
        }
        guard let provenance = run.pendingWorktreeCleanup,
              provenance.sourceProjectPath == workspace.sourceProjectPath,
              provenance.worktreePath == workspace.primaryRoot,
              provenance.branch == preparedWorkspace.branch,
              provenance.ownershipMarkerID == workspace.ownershipMarkerID,
              provenance.ownershipSourceProjectPath == workspace.sourceProjectPath else {
            throw ScheduledTaskRunMaterializationError.missingWorktreeCleanupMetadata
        }
        run.workspaceCleanupProvenance = provenance
    }

    func markTaskShellFailedWithRetry(
        runID: PersistentIdentifier,
        error: Error
    ) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .preparing,
              let thread = run.thread,
              let conversation = thread.conversations.first(where: \.isMain) else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        let failureDate = now()
        run.status = .failure
        run.finishedAt = failureDate
        run.lastError = error.localizedDescription
        run.requiresFinalizationRecovery = false
        thread.modifiedAt = failureDate
        conversation.isUnread = true
        var persistenceError: Error?
        for _ in 0..<provenancePersistenceAttempts {
            do {
                try saveChanges(modelContext)
                failureNotification(error.localizedDescription, conversation.id)
                return
            } catch {
                persistenceError = error
            }
        }
        run.status = .preparing
        run.finishedAt = nil
        run.lastError = nil
        throw persistenceError ?? error
    }

    func makeTaskThread(
        run: ScheduledTaskRun,
        snapshot: ScheduledTaskRunSnapshot,
        preparedWorkspace: PreparedScheduledTaskWorkspace?
    ) -> AgentThread {
        let workspace = preparedWorkspace?.descriptor
        let isProjectThread = snapshot.workspaceKind == .project
        return AgentThread(
            name: snapshot.title,
            hasCustomName: true,
            branch: preparedWorkspace?.branch,
            worktreePath: workspace?.ownershipStrategy == .projectWorktreeOwned ? workspace?.primaryRoot : nil,
            permissionMode: snapshot.permissionMode,
            planModeEnabled: snapshot.planModeEnabled ?? false,
            effort: snapshot.effort,
            model: snapshot.model,
            speedMode: snapshot.speedMode,
            useWorktree: workspace?.ownershipStrategy == .projectWorktreeOwned,
            modifiedAt: now(),
            mode: isProjectThread ? .project : .task,
            taskWorkspaceDescriptor: isProjectThread ? nil : workspace,
            project: snapshot.projectPath.flatMap(modelContext.resolveProject(path:)),
            scheduledTaskRun: run
        )
    }

    func makeScheduledTaskNote(
        run: ScheduledTaskRun,
        snapshot: ScheduledTaskRunSnapshot,
        conversation: Conversation
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            id: "scheduled-task-\(run.id)",
            conversationId: conversation.id,
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: ScheduledTaskOccurrenceNoteFormatter(locale: locale).text(
                title: snapshot.title,
                occurrenceAt: snapshot.occurrenceAt,
                timeZone: snapshot.timeZone
            ),
            timestamp: now(),
            conversation: conversation
        )
    }

    func resetFailedTaskInsertion(
        run: ScheduledTaskRun,
        thread: AgentThread,
        conversation: Conversation,
        note: ConversationEventRecord
    ) {
        run.thread = nil
        run.preparedWorkspaceRoot = nil
        run.preparedWorkspaceOwnershipStrategy = nil
        run.preparedWorkspaceMarkerID = nil
        modelContext.delete(note)
        modelContext.delete(conversation)
        modelContext.delete(thread)
    }

    func requireSnapshotRoots(_ canonicalRoots: [String], equal snapshotRoots: [String]) throws {
        guard canonicalRoots == snapshotRoots else {
            throw ScheduledTaskRunMaterializationError.workspaceRootsChanged
        }
    }

    func requireCurrentWorkspaceIdentities(
        _ workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) throws {
        let roots = [workspaceIdentities.projectRoot].compactMap { $0 } + workspaceIdentities.grantedRoots
        for root in roots {
            guard let currentIdentity = try? workspaceOwnershipService.directoryIdentity(at: root.path),
                  currentIdentity == root.identity else {
                throw ScheduledTaskRunMaterializationError.workspaceRootsChanged
            }
        }
    }
}

struct PreparedScheduledTaskWorkspace {
    let descriptor: TaskWorkspaceDescriptor
    let branch: String?
    let branchOID: String?
    let sourceProjectIdentity: TaskWorkspaceFileSystemIdentity?
}
