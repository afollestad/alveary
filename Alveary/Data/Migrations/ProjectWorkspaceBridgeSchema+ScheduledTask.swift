import Foundation
import SwiftData

/// Frozen additive bridge from pre-folder stores. Change current models instead of these declarations.
extension ProjectWorkspaceBridgeSchema {
    @Model
    final class ScheduledTask {
        @Attribute(.unique) var id: String
        var title: String
        var prompt: String
        var destinationRawValue: String = ScheduledTaskDestination.newThreadPerRun.rawValue
        var revision: Int
        var stateRawValue: String
        var recurrenceKindRawValue: String
        var recurrenceAnchorAt: Date?
        var intervalMinutes: Int?
        var wallClockHour: Int?
        var wallClockMinute: Int?
        var selectedWeekdays: [Int] = ScheduledTaskRecurrence.standardWeekdays
        var weeklyWeekday: Int?
        var monthlyDay: Int?
        var timeZoneIdentifier: String
        var providerID: String
        var model: String?
        var effort: String
        var permissionMode: String
        var workspaceKindRawValue: String
        var workspaceStrategyRawValue: String
        var grantedRoots: [String]
        var nextOccurrenceAt: Date?
        var pendingOccurrenceAt: Date?
        var targetWaitStartedAt: Date?
        var pauseReason: String?
        var lastError: String?
        var createdAt: Date
        var modifiedAt: Date
        var project: Project?
        var targetThread: AgentThread?
        var reusedThread: AgentThread?
        var threadSection: SidebarSection?
        @Relationship(deleteRule: .nullify, inverse: \ScheduledTaskRun.scheduledTask) var runs: [ScheduledTaskRun]
        var workspaceSnapshotJSON: String?

        init() {
            self.id = ""
            self.title = ""
            self.prompt = ""
            self.destinationRawValue = ""
            self.revision = 0
            self.stateRawValue = ""
            self.recurrenceKindRawValue = ""
            self.recurrenceAnchorAt = nil
            self.intervalMinutes = nil
            self.wallClockHour = nil
            self.wallClockMinute = nil
            self.selectedWeekdays = []
            self.weeklyWeekday = nil
            self.monthlyDay = nil
            self.timeZoneIdentifier = ""
            self.providerID = ""
            self.model = nil
            self.effort = ""
            self.permissionMode = ""
            self.workspaceKindRawValue = ""
            self.workspaceStrategyRawValue = ""
            self.grantedRoots = []
            self.nextOccurrenceAt = nil
            self.pendingOccurrenceAt = nil
            self.targetWaitStartedAt = nil
            self.pauseReason = nil
            self.lastError = nil
            self.createdAt = Date(timeIntervalSince1970: 0)
            self.modifiedAt = Date(timeIntervalSince1970: 0)
            self.project = nil
            self.targetThread = nil
            self.reusedThread = nil
            self.threadSection = nil
            self.runs = []
            self.workspaceSnapshotJSON = nil
        }
    }
}
