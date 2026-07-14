import SwiftData
import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func testArchivedTasksSettingsSectionEmpty() {
        assertMacSnapshot(
            ArchivedTasksSettingsSection(
                items: [],
                busyTaskIDs: [],
                errorMessage: nil,
                onDismissError: {},
                onRestore: { _ in },
                onDelete: { _ in }
            )
            .padding(24),
            size: CGSize(width: 820, height: 180),
            named: "settings_archived_tasks_empty"
        )
    }

    func testArchivedTasksSettingsSectionPopulatedNarrow() throws {
        let items = try snapshotArchivedTaskItems()

        assertMacSnapshot(
            ArchivedTasksSettingsSection(
                items: items,
                busyTaskIDs: [],
                errorMessage: nil,
                onDismissError: {},
                onRestore: { _ in },
                onDelete: { _ in }
            )
            .padding(16),
            size: CGSize(width: 400, height: 250),
            named: "settings_archived_tasks_populated_narrow"
        )
    }

    func testArchivedTasksSettingsSectionPopulated() throws {
        let items = try snapshotArchivedTaskItems()

        assertMacSnapshot(
            ArchivedTasksSettingsSection(
                items: items,
                busyTaskIDs: [items[1].id],
                errorMessage: nil,
                onDismissError: {},
                onRestore: { _ in },
                onDelete: { _ in }
            )
            .padding(24),
            size: CGSize(width: 680, height: 250),
            named: "settings_archived_tasks_populated"
        )
    }

    func testArchivedTasksSettingsSectionError() {
        assertMacSnapshot(
            ArchivedTasksSettingsSection(
                items: [],
                busyTaskIDs: [],
                errorMessage: "The task was deleted, but its workspace could not be removed.",
                onDismissError: {},
                onRestore: { _ in },
                onDelete: { _ in }
            )
            .padding(24),
            size: CGSize(width: 680, height: 260),
            named: "settings_archived_tasks_error_dark",
            colorScheme: .dark
        )
    }
}

private extension SnapshotTests {
    func snapshotArchivedTaskItems() throws -> [ArchivedTaskSettingsItem] {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let first = AgentThread(name: "Review weekly release notes", mode: .task)
        let second = AgentThread(name: "Audit dependency updates", mode: .task)
        context.insert(first)
        context.insert(second)
        try context.save()
        return [
            ArchivedTaskSettingsItem(
                id: first.persistentModelID,
                title: first.name,
                archivedAt: Date(timeIntervalSince1970: 1_783_468_800)
            ),
            ArchivedTaskSettingsItem(
                id: second.persistentModelID,
                title: second.name,
                archivedAt: Date(timeIntervalSince1970: 1_783_382_400)
            )
        ]
    }
}
