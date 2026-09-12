import Foundation
import SwiftData

/// Frozen additive bridge from pre-folder stores. Change current models instead of these declarations.
extension ProjectWorkspaceBridgeSchema {
    @Model
    final class SidebarSection {
        @Attribute(.unique) var id: String
        var kindRawValue: String
        var name: String
        var sortOrder: Int
        var createdAt: Date
        @Relationship(deleteRule: .nullify, inverse: \AgentThread.customSection)
        var threads: [AgentThread]
        @Relationship(deleteRule: .nullify, inverse: \ScheduledTask.threadSection)
        var scheduledTasks: [ScheduledTask] = []

        init() {
            self.id = ""
            self.kindRawValue = ""
            self.name = ""
            self.sortOrder = 0
            self.createdAt = Date(timeIntervalSince1970: 0)
            self.threads = []
            self.scheduledTasks = []
        }
    }
}
