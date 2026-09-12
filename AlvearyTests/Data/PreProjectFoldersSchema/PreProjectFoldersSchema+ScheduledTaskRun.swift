import Foundation
import SwiftData

@testable import Alveary

/// Frozen schema before project folders; initializer values do not change the stored schema.
extension PreProjectFoldersSchema {
    @Model
    final class ScheduledTaskRun {
        @Attribute(.unique) var id: String
        @Attribute(.unique) var occurrenceID: String
        @Attribute(.unique) var triggerID: String
        var definitionID: String
        var definitionRevision: Int
        var occurrenceAt: Date
        var triggeredAt: Date
        var triggerKindRawValue: String
        var statusRawValue: String
        var titleSnapshot: String
        var promptSnapshot: String
        var destinationRawValueSnapshot: String = ScheduledTaskDestination.newThreadPerRun.rawValue
        var targetConversationIDSnapshot: String?
        var targetThreadNameSnapshot: String?
        var threadSectionIDSnapshot: String?
        var timeZoneIdentifierSnapshot: String
        var providerIDSnapshot: String
        var modelSnapshot: String?
        var effortSnapshot: String
        var permissionModeSnapshot: String
        var planModeEnabledSnapshot: Bool?
        var speedModeSnapshot: String?
        var workspaceKindRawValueSnapshot: String
        var workspaceStrategyRawValueSnapshot: String
        var projectPathSnapshot: String?
        var projectBaseRefSnapshot: String?
        var projectRemoteNameSnapshot: String?
        var grantedRootsSnapshot: [String]
        var workspaceIdentitySnapshotJSON: String?
        var workspaceCleanupProvenanceJSON: String?
        var preparedWorkspaceRoot: String?
        var preparedOwnershipStrategyRawValue: String?
        var preparedWorkspaceMarkerID: String?
        var pendingWorktreeCleanupSourceProjectPath: String?
        var pendingWorktreeCleanupPath: String?
        var pendingWorktreeCleanupBranch: String?
        var pendingCleanupSourceIdentitySystemNumber: String?
        var pendingCleanupSourceIdentityFileNumber: String?
        var pendingCleanupWorktreeSystemNumber: String?
        var pendingCleanupWorktreeFileNumber: String?
        var pendingWorktreeCleanupBranchIsOwned: Bool?
        var pendingWorktreeCleanupBranchOID: String?
        var pendingWorktreeCleanupOwnershipMarkerID: String?
        var pendingCleanupOwnershipSourceProjectPath: String?
        var claimedAt: Date
        var preparationStartedAt: Date?
        var startedAt: Date?
        var waitingAt: Date?
        var finishedAt: Date?
        var lastError: String?
        var requiresFinalizationRecovery: Bool = false
        var scheduledTask: ScheduledTask?
        @Relationship(deleteRule: .nullify, inverse: \AgentThread.scheduledTaskRun) var thread: AgentThread?
        var targetThread: AgentThread?

        // Frozen schema initializer mirrors every stored property.
        // swiftlint:disable:next function_body_length
        init() {
            self.id = ""
            self.occurrenceID = ""
            self.triggerID = ""
            self.definitionID = ""
            self.definitionRevision = 0
            self.occurrenceAt = Date(timeIntervalSince1970: 0)
            self.triggeredAt = Date(timeIntervalSince1970: 0)
            self.triggerKindRawValue = ""
            self.statusRawValue = ""
            self.titleSnapshot = ""
            self.promptSnapshot = ""
            self.destinationRawValueSnapshot = ""
            self.targetConversationIDSnapshot = nil
            self.targetThreadNameSnapshot = nil
            self.threadSectionIDSnapshot = nil
            self.timeZoneIdentifierSnapshot = ""
            self.providerIDSnapshot = ""
            self.modelSnapshot = nil
            self.effortSnapshot = ""
            self.permissionModeSnapshot = ""
            self.planModeEnabledSnapshot = nil
            self.speedModeSnapshot = nil
            self.workspaceKindRawValueSnapshot = ""
            self.workspaceStrategyRawValueSnapshot = ""
            self.projectPathSnapshot = nil
            self.projectBaseRefSnapshot = nil
            self.projectRemoteNameSnapshot = nil
            self.grantedRootsSnapshot = []
            self.workspaceIdentitySnapshotJSON = nil
            self.workspaceCleanupProvenanceJSON = nil
            self.preparedWorkspaceRoot = nil
            self.preparedOwnershipStrategyRawValue = nil
            self.preparedWorkspaceMarkerID = nil
            self.pendingWorktreeCleanupSourceProjectPath = nil
            self.pendingWorktreeCleanupPath = nil
            self.pendingWorktreeCleanupBranch = nil
            self.pendingCleanupSourceIdentitySystemNumber = nil
            self.pendingCleanupSourceIdentityFileNumber = nil
            self.pendingCleanupWorktreeSystemNumber = nil
            self.pendingCleanupWorktreeFileNumber = nil
            self.pendingWorktreeCleanupBranchIsOwned = nil
            self.pendingWorktreeCleanupBranchOID = nil
            self.pendingWorktreeCleanupOwnershipMarkerID = nil
            self.pendingCleanupOwnershipSourceProjectPath = nil
            self.claimedAt = Date(timeIntervalSince1970: 0)
            self.preparationStartedAt = nil
            self.startedAt = nil
            self.waitingAt = nil
            self.finishedAt = nil
            self.lastError = nil
            self.requiresFinalizationRecovery = false
            self.scheduledTask = nil
            self.thread = nil
            self.targetThread = nil
        }
    }
}
