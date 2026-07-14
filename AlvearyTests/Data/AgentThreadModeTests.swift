import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AgentThreadModeTests: XCTestCase {
    func testExistingInitializerDefaultsToProjectMode() {
        let project = Project(path: "/tmp/project-mode", name: "Project")
        let thread = AgentThread(name: "Project thread", project: project)

        XCTAssertEqual(thread.mode, .project)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
        XCTAssertEqual(thread.primaryWorkingDirectory, CanonicalPath.normalize(project.path))
        XCTAssertEqual(thread.sourceProjectCleanupPath, CanonicalPath.normalize(project.path))
    }

    func testPreTaskModeStoreReopensAsProjectModeWithRelationshipsPreserved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PreTaskModeMigration-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = ModelConfiguration(url: directory.appendingPathComponent("Alveary.store"))
        let projectPath = "/tmp/pre-task-mode-project"
        let conversationID = "pre-task-mode-main"

        try autoreleasepool {
            let legacyContainer = try ModelContainer(
                for: Schema(versionedSchema: PreTaskModeSchema.self),
                configurations: [configuration]
            )
            let context = legacyContainer.mainContext
            let project = PreTaskModeSchema.Project(path: projectPath, name: "Legacy Project")
            let thread = PreTaskModeSchema.AgentThread(name: "Legacy thread", project: project)
            let conversation = PreTaskModeSchema.Conversation(id: conversationID, thread: thread)
            let event = PreTaskModeSchema.ConversationEventRecord(
                id: "pre-task-mode-event",
                conversationId: conversationID,
                conversation: conversation
            )
            project.threads = [thread]
            thread.conversations = [conversation]
            conversation.events = [event]
            context.insert(project)
            try context.save()
        }

        try autoreleasepool {
            let reopenedContainer = try ModelContainer(
                for: Project.self,
                AgentThread.self,
                Conversation.self,
                ConversationEventRecord.self,
                ScheduledTask.self,
                ScheduledTaskRun.self,
                configurations: configuration
            )
            let context = reopenedContainer.mainContext
            let thread = try XCTUnwrap(
                try context.fetch(FetchDescriptor<AgentThread>()).first { $0.name == "Legacy thread" }
            )

            XCTAssertEqual(thread.modeRawValue, AgentThreadMode.project.rawValue)
            XCTAssertEqual(thread.mode, .project)
            assertLegacyTaskWorkspaceDefaults(thread)
            XCTAssertEqual(thread.project?.path, CanonicalPath.normalize(projectPath))
            XCTAssertEqual(thread.conversations.map(\.id), [conversationID])
            XCTAssertEqual(thread.conversations.first?.events.map(\.id), ["pre-task-mode-event"])
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledTask>()), 0)
            XCTAssertEqual(try context.fetchCount(FetchDescriptor<ScheduledTaskRun>()), 0)
        }
    }

    func testProjectModeUsesWorktreeAsPrimaryWorkingDirectory() {
        let project = Project(path: "/tmp/project-mode", name: "Project")
        let thread = AgentThread(
            name: "Worktree thread",
            worktreePath: "/tmp/project-mode-worktree",
            project: project
        )

        XCTAssertEqual(thread.primaryWorkingDirectory, CanonicalPath.normalize("/tmp/project-mode-worktree"))
        XCTAssertEqual(thread.sourceProjectCleanupPath, CanonicalPath.normalize(project.path))
    }

    func testTaskWorkspaceDescriptorRoundTripsThroughFlatPersistedFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let descriptor = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/task-workspace",
            grantedRoots: [
                "/tmp/task-grant",
                "/tmp/task-grant",
                "/tmp/task-workspace"
            ],
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: UUID().uuidString.lowercased(),
            sourceProjectPath: "/tmp/source-project"
        )
        let thread = AgentThread(
            name: "Task thread",
            mode: .task,
            taskWorkspaceDescriptor: descriptor
        )
        context.insert(thread)
        try context.save()

        let fetchedThread = try XCTUnwrap(try context.fetch(FetchDescriptor<AgentThread>()).first)
        XCTAssertNil(fetchedThread.project)
        XCTAssertEqual(fetchedThread.mode, .task)
        XCTAssertEqual(fetchedThread.taskWorkspaceDescriptor, descriptor)
        XCTAssertEqual(fetchedThread.primaryWorkingDirectory, descriptor.primaryRoot)
        XCTAssertEqual(fetchedThread.sourceProjectCleanupPath, descriptor.sourceProjectPath)
    }

    func testPersistedTaskSourcePathIsNotRenormalizedAfterSymlinkReplacement() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("task-source-path-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let movedSourceRoot = root.appendingPathComponent("MovedSource", isDirectory: true)
        let workspaceRoot = root.appendingPathComponent("Workspace", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try makeContainer()
        let context = ModelContext(container)
        let thread = AgentThread(
            name: "Task thread",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: workspaceRoot.path,
                ownershipStrategy: .projectWorktreeOwned,
                ownershipMarkerID: UUID().uuidString.lowercased(),
                sourceProjectPath: sourceRoot.path
            )
        )
        context.insert(thread)
        try context.save()
        try FileManager.default.moveItem(at: sourceRoot, to: movedSourceRoot)
        try FileManager.default.createSymbolicLink(
            atPath: sourceRoot.path,
            withDestinationPath: movedSourceRoot.path
        )

        let fetchedThread = try XCTUnwrap(try context.fetch(FetchDescriptor<AgentThread>()).first)
        XCTAssertEqual(fetchedThread.taskWorkspaceDescriptor?.sourceProjectPath, sourceRoot.path)
        XCTAssertNotEqual(CanonicalPath.normalize(sourceRoot.path), sourceRoot.path)
    }

    func testTaskSourceProjectPathDoesNotCreateProjectDeletionRelationship() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/source-project", name: "Project")
        let projectThread = AgentThread(name: "Project thread", project: project)
        let taskThread = AgentThread(
            name: "Task thread",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/task-workspace",
                ownershipStrategy: .projectWorktreeOwned,
                ownershipMarkerID: UUID().uuidString.lowercased(),
                sourceProjectPath: project.path
            )
        )
        project.threads = [projectThread]
        context.insert(project)
        context.insert(taskThread)
        try context.save()

        context.delete(project)
        try context.save()

        let remainingThreads = try context.fetch(FetchDescriptor<AgentThread>())
        XCTAssertEqual(remainingThreads.map(\.name), ["Task thread"])
        XCTAssertEqual(remainingThreads.first?.sourceProjectCleanupPath, CanonicalPath.normalize("/tmp/source-project"))
    }

    func testUnknownPersistedValuesFailClosed() {
        let thread = AgentThread(name: "Legacy thread")

        thread.modeRawValue = "future-mode"
        thread.taskPrimaryRoot = "/tmp/task-workspace"
        thread.taskWorkspaceOwnershipStrategyRawValue = "future-strategy"

        XCTAssertEqual(thread.mode, .project)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
    }

    func testScheduledRunLinkOverridesEffectiveIdentityWithoutDecodingFallbackWorkspace() {
        let project = Project(path: "/tmp/effective-mode-project", name: "Project")
        let run = makeScheduledRun()
        let thread = AgentThread(
            name: "Scheduled task",
            mode: .project,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/effective-mode-task",
                ownershipStrategy: .privateOwned
            ),
            project: project,
            scheduledTaskRun: run
        )
        run.thread = thread

        XCTAssertEqual(thread.mode, .project)
        XCTAssertEqual(thread.effectiveMode, .task)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
        XCTAssertNil(thread.primaryWorkingDirectory)
        XCTAssertNil(thread.sourceProjectCleanupPath)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func assertLegacyTaskWorkspaceDefaults(_ thread: AgentThread) {
        XCTAssertNil(thread.taskPrimaryRoot)
        XCTAssertEqual(thread.taskGrantedRoots, [])
        XCTAssertNil(thread.taskWorkspaceOwnershipStrategyRawValue)
        XCTAssertNil(thread.taskWorkspaceMarkerID)
        XCTAssertNil(thread.taskSourceProjectPath)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
    }

    private func makeScheduledRun() -> ScheduledTaskRun {
        ScheduledTaskRun(
            occurrenceID: UUID().uuidString,
            definitionID: "effective-mode-definition",
            definitionRevision: 1,
            occurrenceAt: Date(timeIntervalSinceReferenceDate: 1_000),
            triggerKind: .scheduled,
            status: .success,
            titleSnapshot: "Scheduled task",
            promptSnapshot: "Run scheduled work.",
            timeZoneIdentifierSnapshot: "UTC",
            providerIDSnapshot: "codex",
            effortSnapshot: "high",
            permissionModeSnapshot: "default",
            workspaceKindSnapshot: .privateWorkspace,
            workspaceStrategySnapshot: .worktree
        )
    }
}
