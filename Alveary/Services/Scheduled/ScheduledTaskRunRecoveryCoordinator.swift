import Foundation
import SwiftData
@MainActor
final class ScheduledTaskRunRecoveryCoordinator {
    typealias ResumeSafetyCheck = @MainActor (ScheduledTaskRun) -> Bool
    typealias StateSaver = @MainActor (ModelContext) throws -> Void

    let modelContext: ModelContext
    let controllerRegistry: any ConversationControllerRegistry
    let notificationManager: any NotificationManager
    private let workspaceOwnershipService: any TaskWorkspaceOwnershipService
    private let policy: ScheduledTaskRecoveryPolicy
    let noteFormatter: ScheduledTaskOccurrenceNoteFormatter
    private let saveChanges: StateSaver
    init(
        modelContext: ModelContext,
        controllerRegistry: any ConversationControllerRegistry,
        notificationManager: any NotificationManager,
        workspaceOwnershipService: any TaskWorkspaceOwnershipService,
        policy: ScheduledTaskRecoveryPolicy = ScheduledTaskRecoveryPolicy(),
        noteFormatter: ScheduledTaskOccurrenceNoteFormatter = ScheduledTaskOccurrenceNoteFormatter(),
        saveChanges: @escaping StateSaver = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.controllerRegistry = controllerRegistry
        self.notificationManager = notificationManager
        self.workspaceOwnershipService = workspaceOwnershipService
        self.policy = policy
        self.noteFormatter = noteFormatter
        self.saveChanges = saveChanges
    }
    /// Reconciles persisted and already-loaded presentation state without launching work. The caller
    /// materializes and launches returned claims after the rest of startup recovery has completed.
    func recoverPersistedRuns(
        at actionDate: Date,
        isSafeToResume: ResumeSafetyCheck
    ) throws -> ScheduledTaskRunRecoveryResult {
        try flushPreexistingContextChanges()
        let runs = try modelContext.fetch(FetchDescriptor<ScheduledTaskRun>())
        var resumedRunIDs: [PersistentIdentifier] = []
        var interruptedRunIDs: [PersistentIdentifier] = []
        var finalizedRunIDs: [PersistentIdentifier] = []
        var didMutateRecoveryState = false

        for run in runs {
            switch recoveryAction(for: run, at: actionDate, isSafeToResume: isSafeToResume) {
            case .reconcileTerminal:
                if reconcileTerminalRunIfNeeded(run) {
                    finalizedRunIDs.append(run.persistentModelID)
                    didMutateRecoveryState = true
                }
            case .resume:
                resumedRunIDs.append(run.persistentModelID)
            case .interrupt(let message):
                interrupt(run, at: actionDate, reason: message)
                interruptedRunIDs.append(run.persistentModelID)
                didMutateRecoveryState = true
            }
        }

        if didMutateRecoveryState {
            try saveIsolatedRecoveryChanges()
        }
        let publishedRunIDs = interruptedRunIDs + finalizedRunIDs
        if !publishedRunIDs.isEmpty {
            publishRecoveredConversationChanges(
                for: publishedRunIDs,
                refreshBadgeCount: !interruptedRunIDs.isEmpty
            )
        }
        return ScheduledTaskRunRecoveryResult(
            resumedRunIDs: resumedRunIDs,
            interruptedRunIDs: interruptedRunIDs
        )
    }

    /// Synchronously marks in-flight scheduled runs and flushes their shared conversation
    /// controllers. Callers may terminate the returned provider processes only after this returns.
    func prepareForTermination(at actionDate: Date) throws -> ScheduledTaskTerminationPreparation {
        try flushPreexistingContextChanges()
        let runs = try modelContext.fetch(FetchDescriptor<ScheduledTaskRun>()).filter { run in
            guard let status = run.decodedStatus else {
                return true
            }
            return status == .preparing || status == .running || status == .waiting
        }
        let runIDs = runs.map(\.persistentModelID)
        let conversationIDs = runs.compactMap { run in
            presentationConversation(for: run)?.id
        }

        for run in runs {
            interrupt(
                run,
                at: actionDate,
                reason: ScheduledTaskRecoveryInterruptionReason.executionWasInProgress.message
            )
        }
        if !runs.isEmpty {
            try saveIsolatedRecoveryChanges()
        }
        let flushFailures = controllerRegistry.flushForTermination()
        if !runIDs.isEmpty {
            publishRecoveredConversationChanges(for: runIDs, refreshBadgeCount: true)
        }
        return ScheduledTaskTerminationPreparation(
            interruptedRunIDs: runIDs,
            conversationIDsToTerminate: conversationIDs,
            controllerFlushFailures: flushFailures
        )
    }
}

private extension ScheduledTaskRunRecoveryCoordinator {
    func flushPreexistingContextChanges() throws {
        guard modelContext.hasChanges else {
            return
        }
        try saveChanges(modelContext)
    }

    func saveIsolatedRecoveryChanges() throws {
        do {
            try saveChanges(modelContext)
        } catch {
            // The preflight flush above makes this batch recovery-owned, so rolling it back cannot
            // discard another feature's pending changes or leave unpublished terminal state behind.
            modelContext.rollback()
            throw error
        }
    }

    func recoveryReferenceDate(for run: ScheduledTaskRun) -> Date {
        // Run now may consume an older cadence occurrence, so its recovery window
        // starts when the user explicitly triggered it rather than at that occurrence.
        run.triggerKind == .runNow ? run.triggeredAt : run.occurrenceAt
    }

    func recoveryAction(
        for run: ScheduledTaskRun,
        at actionDate: Date,
        isSafeToResume: ResumeSafetyCheck
    ) -> ScheduledTaskPersistedRunRecoveryAction {
        guard let status = run.decodedStatus else {
            return .interrupt("The scheduled task run has an invalid persisted status.")
        }
        guard !status.isTerminal else {
            return .reconcileTerminal
        }
        guard run.decodedDestinationSnapshot != nil else {
            return .interrupt("The scheduled task run has an invalid persisted destination.")
        }
        let decision = policy.decision(
            status: status,
            recoveryReferenceAt: recoveryReferenceDate(for: run),
            at: actionDate,
            isSafeToResume: resumeSafetyAllows(
                run,
                status: status,
                externalCheck: isSafeToResume
            )
        )
        switch decision {
        case .ignoreTerminal:
            return .reconcileTerminal
        case .resumeClaimed:
            return .resume
        case .interrupt(let reason):
            return .interrupt(reason.message)
        }
    }

    func resumeSafetyAllows(
        _ run: ScheduledTaskRun,
        status: ScheduledTaskRunStatus,
        externalCheck: ResumeSafetyCheck
    ) -> Bool {
        let targetIsValid: Bool
        switch run.decodedDestinationSnapshot {
        case .newThread:
            targetIsValid = true
        case .existingThread:
            targetIsValid = run.targetThread?.isPinned == true &&
                run.targetThread?.archivedAt == nil &&
                presentationConversation(for: run) != nil
        case nil:
            targetIsValid = false
        }
        return status == .claimed &&
            run.triggerKind != nil &&
            targetIsValid &&
            run.hasValidWorkspaceIdentityProvenance &&
            run.workspaceIdentitySnapshot.map(workspaceIdentitiesAreCurrent) == true &&
            externalCheck(run)
    }

    func reconcileTerminalRunIfNeeded(_ run: ScheduledTaskRun) -> Bool {
        guard run.requiresFinalizationRecovery else {
            return false
        }
        _ = supersedePendingInteractions(for: run)
        run.requiresFinalizationRecovery = false
        return true
    }

    func interrupt(
        _ run: ScheduledTaskRun,
        at actionDate: Date,
        reason: String
    ) {
        switch run.decodedDestinationSnapshot {
        case .newThread where run.thread == nil:
            createInterruptedTaskShell(for: run, at: actionDate)
        case .newThread:
            sanitizeExistingWorkspace(for: run)
        case .existingThread:
            insertInterruptedOccurrenceNoteIfNeeded(for: run, at: actionDate)
        case nil:
            break
        }
        run.status = .interrupted
        run.finishedAt = actionDate
        run.lastError = reason
        run.requiresFinalizationRecovery = false
        let presentationConversation = presentationConversation(for: run)
        let presentationThread = presentationConversation?.thread
        presentationThread?.modifiedAt = actionDate
        presentationConversation?.isUnread = true
        supersedePendingInteractions(for: run)
    }

    func createInterruptedTaskShell(
        for run: ScheduledTaskRun,
        at actionDate: Date
    ) {
        let workspace: TaskWorkspaceDescriptor?
        if run.hasPendingWorktreeCleanupMetadata {
            workspace = nil
            clearPreparedWorkspaceMetadataIfCleanupIsComplete(for: run)
        } else {
            workspace = recoveredWorkspaceDescriptor(for: run)
        }
        let isWorktree = workspace?.ownershipStrategy == .projectWorktreeOwned
        let project = run.projectPathSnapshot.flatMap(modelContext.resolveProject(path:))
        let isProjectThread = run.workspaceKindSnapshot == .project && project != nil
        let thread = AgentThread(
            name: run.titleSnapshot,
            hasCustomName: true,
            worktreePath: isWorktree ? workspace?.primaryRoot : nil,
            permissionMode: run.permissionModeSnapshot,
            planModeEnabled: run.planModeEnabledSnapshot ?? false,
            effort: run.effortSnapshot,
            model: run.modelSnapshot,
            speedMode: run.speedModeSnapshot,
            useWorktree: isWorktree,
            modifiedAt: actionDate,
            mode: isProjectThread ? .project : .task,
            taskWorkspaceDescriptor: !isProjectThread || isWorktree ? workspace : nil,
            project: project,
            scheduledTaskRun: run
        )
        if isProjectThread && !isWorktree {
            thread.taskGrantedRoots = workspace?.grantedRoots ?? []
        }
        let conversation = Conversation(
            provider: run.providerIDSnapshot,
            isMain: true,
            displayOrder: 0,
            isUnread: true,
            thread: thread
        )
        let note = makeInterruptedOccurrenceNote(for: run, conversation: conversation, at: actionDate)
        thread.conversations = [conversation]
        conversation.events = [note]
        run.thread = thread
        modelContext.insert(thread)
        modelContext.insert(conversation)
        modelContext.insert(note)
    }

    func sanitizeExistingWorkspace(for run: ScheduledTaskRun) {
        guard let thread = run.thread else {
            return
        }
        guard let workspaceKind = run.workspaceKindSnapshot,
              run.workspaceStrategySnapshot != nil else {
            withholdWorkspace(from: thread)
            return
        }
        if run.hasPendingWorktreeCleanupMetadata {
            withholdWorkspace(from: thread)
            clearPreparedWorkspaceMetadataIfCleanupIsComplete(for: run)
            return
        }
        guard let workspace = thread.taskWorkspaceDescriptor else {
            return
        }
        let identities = run.workspaceIdentitySnapshot
        let expectedSourceProjectPath = workspace.ownershipStrategy == .privateOwned
            ? nil
            : run.projectPathSnapshot
        let workspaceIsValid = workspace.primaryRoot == run.preparedWorkspaceRoot &&
            workspace.ownershipStrategy == run.preparedWorkspaceOwnershipStrategy &&
            workspace.ownershipMarkerID == run.preparedWorkspaceMarkerID &&
            workspace.sourceProjectPath == expectedSourceProjectPath &&
            workspace.grantedRoots == run.grantedRootsSnapshot &&
            identities?.matchesConfiguration(
                workspaceKind: workspaceKind,
                projectPath: run.projectPathSnapshot,
                grantedRootPaths: run.grantedRootsSnapshot
            ) == true &&
            identities.flatMap { validatedRecoveredDescriptor(workspace, workspaceIdentities: $0) } != nil
        guard !workspaceIsValid else {
            return
        }
        withholdWorkspace(from: thread)
    }

    func clearPreparedWorkspaceMetadataIfCleanupIsComplete(for run: ScheduledTaskRun) {
        guard run.pendingWorktreeCleanup != nil else {
            return
        }
        run.preparedWorkspaceRoot = nil
        run.preparedWorkspaceOwnershipStrategy = nil
        run.preparedWorkspaceMarkerID = nil
    }

    func withholdWorkspace(from thread: AgentThread) {
        thread.taskWorkspaceDescriptor = nil
        thread.worktreePath = nil
        thread.branch = nil
        thread.useWorktree = false
    }

    func recoveredWorkspaceDescriptor(for run: ScheduledTaskRun) -> TaskWorkspaceDescriptor? {
        guard let workspaceKind = run.workspaceKindSnapshot,
              run.workspaceStrategySnapshot != nil,
              let root = canonicalAbsolutePath(run.preparedWorkspaceRoot),
              let expectedOwnershipStrategy = expectedOwnershipStrategy(for: run),
              run.preparedWorkspaceOwnershipStrategy == expectedOwnershipStrategy,
              let workspaceIdentities = run.workspaceIdentitySnapshot,
              workspaceIdentities.matchesConfiguration(
                  workspaceKind: workspaceKind,
                  projectPath: run.projectPathSnapshot,
                  grantedRootPaths: run.grantedRootsSnapshot
              )
        else {
            return nil
        }
        return makeRecoveredWorkspaceDescriptor(
            run: run,
            root: root,
            ownershipStrategy: expectedOwnershipStrategy,
            workspaceIdentities: workspaceIdentities
        )
    }

    func expectedOwnershipStrategy(for run: ScheduledTaskRun) -> TaskWorkspaceOwnershipStrategy? {
        guard let workspaceKind = ScheduledTaskWorkspaceKind(rawValue: run.workspaceKindRawValueSnapshot),
              let workspaceStrategy = ScheduledTaskWorkspaceStrategy(rawValue: run.workspaceStrategyRawValueSnapshot) else {
            return nil
        }
        switch (workspaceKind, workspaceStrategy) {
        case (.privateWorkspace, _):
            return .privateOwned
        case (.project, .localCheckout):
            return .projectLocal
        case (.project, .worktree):
            return .projectWorktreeOwned
        }
    }

    func makeRecoveredWorkspaceDescriptor(
        run: ScheduledTaskRun,
        root: String,
        ownershipStrategy: TaskWorkspaceOwnershipStrategy,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) -> TaskWorkspaceDescriptor? {
        let sourceProjectPath = ownershipStrategy == .privateOwned
            ? nil
            : canonicalAbsolutePath(run.projectPathSnapshot)
        if ownershipStrategy != .privateOwned, sourceProjectPath == nil {
            return nil
        }
        if ownershipStrategy == .projectLocal, sourceProjectPath != root {
            return nil
        }
        let markerID = recoveredMarkerID(
            run.preparedWorkspaceMarkerID,
            root: root,
            ownershipStrategy: ownershipStrategy
        )
        if ownershipStrategy != .projectLocal, markerID == nil {
            return nil
        }
        if ownershipStrategy == .projectLocal, run.preparedWorkspaceMarkerID != nil {
            return nil
        }
        let grants = run.grantedRootsSnapshot.compactMap(canonicalAbsolutePath)
        guard grants.count == run.grantedRootsSnapshot.count,
              Set(grants).count == grants.count,
              !grants.contains(root) else {
            return nil
        }
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: root,
            grantedRoots: grants,
            ownershipStrategy: ownershipStrategy,
            ownershipMarkerID: markerID,
            sourceProjectPath: sourceProjectPath
        )
        guard descriptor.grantedRoots == run.grantedRootsSnapshot else {
            return nil
        }
        return validatedRecoveredDescriptor(
            descriptor,
            workspaceIdentities: workspaceIdentities
        )
    }

    func validatedRecoveredDescriptor(
        _ descriptor: TaskWorkspaceDescriptor,
        workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) -> TaskWorkspaceDescriptor? {
        guard workspaceIdentitiesAreCurrent(workspaceIdentities) else {
            return nil
        }
        guard descriptor.ownershipStrategy != .projectLocal else {
            return descriptor
        }
        do {
            try workspaceOwnershipService.validateOwnedWorkspace(descriptor)
            if descriptor.ownershipStrategy == .projectWorktreeOwned {
                guard let claimedSourceIdentity = workspaceIdentities.projectRoot?.identity,
                      try workspaceOwnershipService.sourceProjectIdentity(
                          forOwnedWorktree: descriptor
                      ) == claimedSourceIdentity else {
                    return nil
                }
            }
            return descriptor
        } catch {
            return nil
        }
    }

    func workspaceIdentitiesAreCurrent(
        _ workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
    ) -> Bool {
        let roots = [workspaceIdentities.projectRoot].compactMap { $0 } + workspaceIdentities.grantedRoots
        return roots.allSatisfy { root in
            guard NSString(string: root.path).isAbsolutePath,
                  CanonicalPath.normalize(root.path) == root.path,
                  let currentIdentity = try? workspaceOwnershipService.directoryIdentity(at: root.path) else {
                return false
            }
            return currentIdentity == root.identity
        }
    }

    func canonicalAbsolutePath(_ path: String?) -> String? {
        guard let path,
              NSString(string: path).isAbsolutePath,
              CanonicalPath.normalize(path) == path else {
            return nil
        }
        return path
    }

    func recoveredMarkerID(
        _ markerID: String?,
        root: String,
        ownershipStrategy: TaskWorkspaceOwnershipStrategy
    ) -> String? {
        if let markerID = normalizedMarkerID(markerID) {
            return markerID
        }
        guard ownershipStrategy == .privateOwned else {
            return nil
        }
        return normalizedMarkerID(URL(fileURLWithPath: root, isDirectory: true).lastPathComponent)
    }

    func normalizedMarkerID(_ markerID: String?) -> String? {
        guard let markerID,
              let uuid = UUID(uuidString: markerID),
              uuid.uuidString.lowercased() == markerID.lowercased() else {
            return nil
        }
        return uuid.uuidString.lowercased()
    }

}

private enum ScheduledTaskPersistedRunRecoveryAction {
    case reconcileTerminal
    case resume
    case interrupt(String)
}
