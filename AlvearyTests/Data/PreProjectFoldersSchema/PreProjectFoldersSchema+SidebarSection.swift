import Foundation
import SwiftData

@testable import Alveary

/// Frozen schema before project folders; initializer values do not change the stored schema.
extension PreProjectFoldersSchema {
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
