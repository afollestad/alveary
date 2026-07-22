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
        providerDiscovery: any AgentProviderDiscoveryService,
        workspaceOwnershipService: any TaskWorkspaceOwnershipService,
        worktreeManager: any WorktreeManager,
        targetIsReady: @escaping @MainActor @Sendable (String) -> Bool = { _ in true },
        fileManager: FileManager = .default
    ) {
        let preflightValidator = DefaultScheduledTaskPreflightValidator(
            providerDiscovery: providerDiscovery,
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
        guard let target = snapshot.preflight.target else {
            return true
        }
        return targetIsReady(target.conversationID)
    }
}
