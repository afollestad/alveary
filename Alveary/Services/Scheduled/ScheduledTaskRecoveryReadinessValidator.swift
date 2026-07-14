import AgentCLIKit
import Foundation

struct ScheduledTaskRecoveryReadinessSnapshot: Equatable, Sendable {
    let runID: String
    let preflight: ScheduledTaskPreflightSnapshot
    let claimedWorkspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot
}

struct ScheduledTaskRecoveryReadinessValidator: Sendable {
    private let validatePreflight: ScheduledTaskPreflightValidator

    init(
        providerDiscovery: any AgentProviderDiscoveryService,
        workspaceOwnershipService: any TaskWorkspaceOwnershipService,
        worktreeManager: any WorktreeManager,
        fileManager: FileManager = .default
    ) {
        let preflightValidator = DefaultScheduledTaskPreflightValidator(
            providerDiscovery: providerDiscovery,
            workspaceOwnershipService: workspaceOwnershipService,
            worktreeManager: worktreeManager,
            fileManager: fileManager
        )
        self.validatePreflight = preflightValidator.validate
    }

    init(validatePreflight: @escaping ScheduledTaskPreflightValidator) {
        self.validatePreflight = validatePreflight
    }

    @MainActor
    func isReady(_ snapshot: ScheduledTaskRecoveryReadinessSnapshot) async -> Bool {
        guard case let .ready(currentWorkspaceIdentities) = await validatePreflight(snapshot.preflight) else {
            return false
        }
        return currentWorkspaceIdentities == snapshot.claimedWorkspaceIdentities
    }
}
