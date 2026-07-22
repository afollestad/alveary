import Foundation
import SwiftData

struct ScheduledTaskRunSnapshot {
    let title: String
    let prompt: String
    let destination: ScheduledTaskDestination
    let targetConversationID: String?
    let occurrenceAt: Date
    let timeZone: TimeZone
    let providerID: String
    let model: String?
    let effort: String
    let permissionMode: String
    let planModeEnabled: Bool?
    let speedMode: String?
    let workspaceKind: ScheduledTaskWorkspaceKind
    let workspaceStrategy: ScheduledTaskWorkspaceStrategy
    let projectPath: String?
    let projectBaseRef: String?
    let projectRemoteName: String?
    let grantedRoots: [String]
    let workspaceIdentities: ScheduledTaskWorkspaceIdentitySnapshot?
}

extension DefaultScheduledTaskRunMaterializer {
    func transitionToPreparing(runID: PersistentIdentifier) throws -> ScheduledTaskRunSnapshot {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID) else {
            throw ScheduledTaskRunMaterializationError.runMissing
        }
        guard run.status == .claimed else {
            throw ScheduledTaskRunMaterializationError.invalidRunStatus(run.status)
        }

        let snapshot = try makeSnapshot(run)
        run.status = .preparing
        run.preparationStartedAt = now()
        return snapshot
    }

    func makeSnapshot(_ run: ScheduledTaskRun) throws -> ScheduledTaskRunSnapshot {
        guard let destination = run.decodedDestinationSnapshot else {
            throw ScheduledTaskRunMaterializationError.invalidDestination(
                run.destinationRawValueSnapshot
            )
        }
        guard let timeZone = TimeZone(identifier: run.timeZoneIdentifierSnapshot) else {
            throw ScheduledTaskRunMaterializationError.invalidTimeZone(run.timeZoneIdentifierSnapshot)
        }
        guard let workspaceKind = run.workspaceKindSnapshot,
              let workspaceStrategy = run.workspaceStrategySnapshot else {
            throw ScheduledTaskRunMaterializationError.invalidWorkspaceConfiguration(
                kind: run.workspaceKindRawValueSnapshot,
                strategy: run.workspaceStrategyRawValueSnapshot
            )
        }
        return makeSnapshot(
            run,
            destination: destination,
            timeZone: timeZone,
            workspaceKind: workspaceKind,
            workspaceStrategy: workspaceStrategy
        )
    }

    func makeSnapshot(
        _ run: ScheduledTaskRun,
        destination: ScheduledTaskDestination,
        timeZone: TimeZone,
        workspaceKind: ScheduledTaskWorkspaceKind,
        workspaceStrategy: ScheduledTaskWorkspaceStrategy
    ) -> ScheduledTaskRunSnapshot {
        ScheduledTaskRunSnapshot(
            title: run.titleSnapshot,
            prompt: run.promptSnapshot,
            destination: destination,
            targetConversationID: run.targetConversationIDSnapshot,
            occurrenceAt: run.occurrenceAt,
            timeZone: timeZone,
            providerID: run.providerIDSnapshot,
            model: run.modelSnapshot,
            effort: run.effortSnapshot,
            permissionMode: run.permissionModeSnapshot,
            planModeEnabled: run.planModeEnabledSnapshot,
            speedMode: run.speedModeSnapshot,
            workspaceKind: workspaceKind,
            workspaceStrategy: workspaceStrategy,
            projectPath: run.projectPathSnapshot,
            projectBaseRef: run.projectBaseRefSnapshot,
            projectRemoteName: run.projectRemoteNameSnapshot,
            grantedRoots: run.grantedRootsSnapshot,
            workspaceIdentities: run.workspaceIdentitySnapshot
        )
    }

    func persistInvalidSnapshotFailure(
        runID: PersistentIdentifier,
        error: Error
    ) throws {
        guard let run = modelContext.resolveScheduledTaskRun(id: runID),
              run.status == .claimed else {
            throw ScheduledTaskRunMaterializationError.runChangedDuringPreparation
        }
        guard run.decodedDestinationSnapshot == .newThread else {
            return
        }
        let fallbackTimeZone = TimeZone(identifier: run.timeZoneIdentifierSnapshot)
            ?? TimeZone(secondsFromGMT: 0)
            ?? .current
        let snapshot = makeSnapshot(
            run,
            destination: .newThread,
            timeZone: fallbackTimeZone,
            workspaceKind: run.workspaceKindSnapshot ?? .privateWorkspace,
            workspaceStrategy: run.workspaceStrategySnapshot ?? .localCheckout
        )
        run.status = .preparing
        run.preparationStartedAt = now()
        try persistTaskShellWithRetry(runID: runID, snapshot: snapshot)
        try markTaskShellFailedWithRetry(runID: runID, error: error)
    }
}
