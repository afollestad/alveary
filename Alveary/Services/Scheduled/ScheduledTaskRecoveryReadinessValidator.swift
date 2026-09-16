import AgentCLIKit
import Foundation

struct ScheduledTaskRecoveryReadinessSnapshot: Equatable, Sendable {
    let runID: String
    let claimedAt: Date
    let preflight: ScheduledTaskPreflightSnapshot
    let claimedWorkspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
}

struct ScheduledTaskRecoveryReadinessValidator: Sendable {
    private let validatePreflight: ScheduledTaskPreflightValidator
    private let targetIsReady: @MainActor @Sendable (String) -> Bool

    init(
        harnessDiscovery: any AgentHarnessDiscoveryService,
        workspaceOwnershipService: any TaskWorkspaceOwnershipService,
        worktreeManager: any WorktreeManager,
        targetIsReady: @escaping @MainActor @Sendable (String) -> Bool = { _ in true },
        fileManager: FileManager = .default
    ) {
        let preflightValidator = DefaultScheduledTaskPreflightValidator(
            harnessDiscovery: harnessDiscovery,
            workspaceOwnershipService: workspaceOwnershipService,
            worktreeManager: worktreeManager,
            fileManager: fileManager
        )
        self.validatePreflight = preflightValidator.validate
        self.targetIsReady = targetIsReady
    }

    init(
        validatePreflight: @escaping ScheduledTaskPreflightValidator,
        targetIsReady: @escaping @MainActor @Sendable (String) -> Bool = { _ in true }
    ) {
        self.validatePreflight = validatePreflight
        self.targetIsReady = targetIsReady
    }

    @MainActor
    func isReady(_ snapshot: ScheduledTaskRecoveryReadinessSnapshot) async -> Bool {
        guard targetIsAvailable(for: snapshot) else {
            return false
        }
        guard case let .ready(currentWorkspaceIdentities) = await validatePreflight(snapshot.preflight) else {
            return false
        }
        return currentWorkspaceIdentities == snapshot.claimedWorkspaceIdentities &&
            targetIsAvailable(for: snapshot)
    }

    @MainActor
    private func targetIsAvailable(for snapshot: ScheduledTaskRecoveryReadinessSnapshot) -> Bool {
        guard let conversationID = snapshot.preflight.gatedConversationID else {
            return true
        }
        return targetIsReady(conversationID)
    }
}

/// Captures persisted recovery targets without changing the source roots used for workspace ownership.
extension ScheduledTaskRecoveryReadinessSnapshot {
    static func recoveryPrecedes(
        _ lhs: ScheduledTaskRecoveryReadinessSnapshot,
        _ rhs: ScheduledTaskRecoveryReadinessSnapshot
    ) -> Bool {
        if lhs.claimedAt != rhs.claimedAt {
            return lhs.claimedAt < rhs.claimedAt
        }
        if lhs.preflight.scheduledOccurrenceAt != rhs.preflight.scheduledOccurrenceAt {
            return lhs.preflight.scheduledOccurrenceAt < rhs.preflight.scheduledOccurrenceAt
        }
        return lhs.runID < rhs.runID
    }

    /// The conversation gating this run's recovery; recovery dedupes on it so two runs cannot resume into one thread.
    var gatedTargetConversationID: String? {
        preflight.gatedConversationID
    }

    @MainActor
    init?(_ run: ScheduledTaskRun) {
        guard let destination = run.decodedDestinationSnapshot,
              let workspaceKind = run.workspaceKindSnapshot,
              let workspaceStrategy = run.workspaceStrategySnapshot,
              let claimedWorkspaceIdentities = run.workspaceIdentitySnapshot else {
            return nil
        }
        runID = run.id
        claimedAt = run.claimedAt
        preflight = ScheduledTaskPreflightSnapshot(
            definitionID: run.definitionID,
            definitionRevision: run.definitionRevision,
            scheduledOccurrenceAt: run.occurrenceAt,
            recurrence: .once(run.occurrenceAt),
            timeZoneIdentifier: run.timeZoneIdentifierSnapshot,
            harnessID: run.harnessIDSnapshot,
            model: run.modelSnapshot,
            effort: run.effortSnapshot,
            permissionMode: run.permissionModeSnapshot,
            workspaceKind: workspaceKind,
            workspaceStrategy: workspaceStrategy,
            projectPath: run.projectPathSnapshot,
            projectBaseRef: run.projectBaseRefSnapshot,
            projectRemoteName: run.projectRemoteNameSnapshot,
            grantedRoots: run.grantedRootsSnapshot,
            destination: destination,
            target: run.recoveryTargetSnapshot,
            reusedTarget: run.recoveryReusedTarget
        )
        self.claimedWorkspaceIdentities = claimedWorkspaceIdentities
    }
}

private extension ScheduledTaskRun {
    /// Conversation identity for a claimed `.reusedThread` run's recovery gating; nil once the
    /// materialization self-heal detached the target, when recovery treats it as a creating run.
    @MainActor
    var recoveryReusedTarget: ScheduledTaskReusedTarget? {
        guard decodedDestinationSnapshot == .reusedThread,
              let conversationID = targetConversationIDSnapshot,
              let targetThread else {
            return nil
        }
        return ScheduledTaskReusedTarget(
            conversationID: conversationID,
            threadName: targetThreadNameSnapshot ?? targetThread.displayName(),
            threadID: targetThread.persistentModelID,
            harnessDiscoveryDirectory: harnessIDSnapshot == "opencode" && targetThread.isHealthyReusedScheduledTaskTarget
                ? targetThread.primaryWorkingDirectory : nil
        )
    }

    @MainActor
    var recoveryTargetSnapshot: ScheduledTaskTargetSnapshot? {
        guard decodedDestinationSnapshot == .existingThread,
              let conversationID = targetConversationIDSnapshot else {
            return nil
        }
        return ScheduledTaskTargetSnapshot(
            conversationID: conversationID,
            threadName: targetThreadNameSnapshot ?? targetThread?.displayName() ?? "Existing thread",
            harnessID: harnessIDSnapshot,
            model: modelSnapshot,
            effort: effortSnapshot,
            permissionMode: permissionModeSnapshot,
            planModeEnabled: planModeEnabledSnapshot ?? false,
            speedMode: speedModeSnapshot ?? AgentSpeedMode.standard.rawValue,
            workspaceKind: workspaceKindSnapshot ?? .project,
            workspaceStrategy: workspaceStrategySnapshot ?? .localCheckout,
            projectPath: projectPathSnapshot,
            grantedRoots: grantedRootsSnapshot
        )
    }
}
