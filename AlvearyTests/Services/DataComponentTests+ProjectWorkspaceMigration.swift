import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension DataComponentTests {
    func testCurrentStoreMigratesHistoryMembershipAndWorkspaceSnapshots() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Alveary.store")
        try writePreFolderStore(at: url)
        let identity = try autoreleasepool {
            let container = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
            let context = container.mainContext
            let project = try XCTUnwrap(context.fetch(FetchDescriptor<Project>()).first)
            let thread = try XCTUnwrap(context.fetch(FetchDescriptor<AgentThread>()).first)
            let schedule = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledTask>()).first)
            let run = try XCTUnwrap(context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
            XCTAssertNotNil(UUID(uuidString: project.id))
            XCTAssertEqual(project.orderedFolders.map(\.path), ["/missing/source"])
            XCTAssertEqual(project.primaryFolder?.remoteName, "upstream")
            XCTAssertEqual(thread.primaryWorkingDirectory, "/missing/worktree")
            XCTAssertEqual(thread.sourceFolder?.path, "/missing/source")
            XCTAssertEqual(thread.workspaceSnapshot?.grants.map(\.path), ["/missing/grant"])
            XCTAssertEqual(thread.workspaceSnapshot?.rootsExplicitlyManaged, true)
            XCTAssertEqual(thread.conversations.first?.providerSessionId, "saved-session")
            XCTAssertEqual(thread.conversations.first?.events.first?.content, "Keep this history")
            XCTAssertEqual(thread.linkedPullRequestsJSON, "saved-links")
            XCTAssertEqual(schedule.workspaceSnapshot?.grants.map(\.path), ["/missing/schedule-grant"])
            XCTAssertEqual(run.workspaceSnapshot?.primarySource?.path, "/original/run-source")
            XCTAssertEqual(run.workspaceSnapshot?.grants.map(\.path), ["/original/run-grant"])
            XCTAssertEqual(run.pendingWorktreeCleanupPath, "/original/cleanup")
            XCTAssertEqual(run.scheduledTask?.id, schedule.id)
            XCTAssertEqual(run.thread?.conversations.first?.id, "saved-conversation")
            project.folders = []
            project.primaryFolderID = nil
            try context.save()
            XCTAssertEqual(thread.primaryWorkingDirectory, "/missing/worktree")
            XCTAssertEqual(thread.sourceFolder?.path, "/missing/source")
            return project.id
        }
        let reopened = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
        XCTAssertEqual(try reopened.mainContext.fetch(FetchDescriptor<Project>()).first?.id, identity)
        XCTAssertEqual(try reopened.mainContext.fetchCount(FetchDescriptor<ConversationEventRecord>()), 1)
    }

    func testFailedBridgeMigrationPreservesOriginalAndCanRetry() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Alveary.store")
        try writePreFolderStore(at: url)
        let originals = try storeBytes(at: url)
        XCTAssertThrowsError(try ProjectWorkspaceStoreUpgrade.open(at: url, validateBridge: { _ in
            throw CocoaError(.validationMissingMandatoryProperty)
        }))
        XCTAssertEqual(try storeBytes(at: url), originals)
        let container = try DataComponent.openModelContainer(isStoredInMemoryOnly: false, persistentStoreURL: url)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ConversationEventRecord>()), 1)
    }

    func testReviewTeamRunHistorySurvivesBridgeMigrationAndReopen() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Alveary.store")
        let reviewRunJSON = #"{"id":"saved-review-run","phase":"awaitingDecision","history":[{"id":"saved-attempt"}]}"#
        try writePreFolderStore(at: url, reviewRunJSON: reviewRunJSON)
        try autoreleasepool {
            let migrated = try ProjectWorkspaceStoreUpgrade.open(at: url)
            let conversation = try XCTUnwrap(migrated.mainContext.fetch(FetchDescriptor<Conversation>()).first)
            XCTAssertEqual(conversation.pullRequestReviewRunJSON, reviewRunJSON)
        }
        let reopened = try ProjectWorkspaceStoreUpgrade.open(at: url)
        let conversation = try XCTUnwrap(reopened.mainContext.fetch(FetchDescriptor<Conversation>()).first)
        XCTAssertEqual(conversation.pullRequestReviewRunJSON, reviewRunJSON)
    }

    func testInterruptedInstallationRestoresTheBackupBeforeRetrying() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Alveary.store")
        try writePreFolderStore(at: url)
        XCTAssertThrowsError(try ProjectWorkspaceStoreUpgrade.open(at: url, validateBridge: { _ in
            throw CocoaError(.validationMissingMandatoryProperty)
        }))
        let staging = root.appendingPathComponent(".Alveary.store-folder-upgrade")
        try "installing".write(to: staging.appendingPathComponent("state"), atomically: true, encoding: .utf8)
        try Data("interrupted database copy".utf8).write(to: url)
        let container = try ProjectWorkspaceStoreUpgrade.open(at: url)
        XCTAssertEqual(try container.mainContext.fetchCount(FetchDescriptor<ConversationEventRecord>()), 1)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Conversation>()).first?.providerSessionId, "saved-session")
    }

    func testMigrationDoesNotFollowAChangedSymlink() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("original")
        let replacement = root.appendingPathComponent("replacement")
        let link = root.appendingPathComponent("saved-source")
        try FileManager.default.createDirectory(at: original, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacement, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        let url = root.appendingPathComponent("Alveary.store")
        try writePreFolderStore(at: url, sourcePath: link.path)
        try FileManager.default.removeItem(at: link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: replacement)
        let container = try ProjectWorkspaceStoreUpgrade.open(at: url)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<Project>()).first?.primaryFolder?.path, link.path)
        XCTAssertEqual(try container.mainContext.fetch(FetchDescriptor<AgentThread>()).first?.sourceFolder?.path, link.path)
    }

    func testUnsupportedStoreVersionsCannotBeDowngraded() {
        XCTAssertNoThrow(try ProjectWorkspaceStoreUpgrade.validateStoreVersions([]))
        XCTAssertNoThrow(try ProjectWorkspaceStoreUpgrade.validateStoreVersions(["1.0.0"]))
        XCTAssertThrowsError(try ProjectWorkspaceStoreUpgrade.validateStoreVersions(["3.1.0"]))
        XCTAssertThrowsError(try ProjectWorkspaceStoreUpgrade.validateStoreVersions(["4.0.0"]))
    }

    func testBorrowedTaskMigrationKeepsMetadataFromItsSavedSource() throws {
        let root = try makeRecoveryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Alveary.store")
        try writePreFolderStore(at: url, taskWithoutProject: true)
        let container = try ProjectWorkspaceStoreUpgrade.open(at: url)
        let thread = try XCTUnwrap(container.mainContext.fetch(FetchDescriptor<AgentThread>()).first)
        XCTAssertNil(thread.project)
        XCTAssertEqual(thread.sourceFolder?.path, "/missing/source")
        XCTAssertEqual(thread.sourceFolder?.remoteName, "upstream")
        XCTAssertEqual(thread.workspaceFolderTargets.first?.repository, "owner/repository")
        XCTAssertEqual(thread.taskWorkspaceDescriptor?.sourceProjectPath, "/missing/source")
    }

    private func writePreFolderStore(
        at url: URL, sourcePath: String = "/missing/source", taskWithoutProject: Bool = false, reviewRunJSON: String? = nil
    ) throws {
        try autoreleasepool {
            let container = try ModelContainer(for: Schema(versionedSchema: PreProjectFoldersSchema.self), configurations: .init(url: url))
            let context = container.mainContext
            let project = PreProjectFoldersSchema.Project()
            project.path = sourcePath
            project.name = "Original"
            project.remoteName = "upstream"
            project.gitRemote = "git@github.com:owner/repository.git"
            project.baseRef = "upstream/main"
            let thread = PreProjectFoldersSchema.AgentThread()
            thread.name = "Existing thread"
            thread.worktreePath = "/missing/worktree"
            thread.modeRawValue = taskWithoutProject ? "task" : "project"
            thread.taskSourceProjectPath = taskWithoutProject ? sourcePath : nil
            thread.taskPrimaryRoot = taskWithoutProject ? thread.worktreePath : nil
            thread.taskWorkspaceOwnershipStrategyRawValue = taskWithoutProject ? "projectLocal" : nil
            thread.taskGrantedRoots = ["/missing/grant"]
            thread.linkedPullRequestsJSON = "saved-links"
            thread.project = taskWithoutProject ? nil : project
            let conversation = PreProjectFoldersSchema.Conversation()
            conversation.id = "saved-conversation"
            conversation.providerSessionId = "saved-session"
            conversation.pullRequestReviewRunJSON = reviewRunJSON
            conversation.thread = thread
            let event = PreProjectFoldersSchema.ConversationEventRecord()
            event.id = "saved-event"
            event.conversationId = conversation.id
            event.type = "message"
            event.content = "Keep this history"
            event.conversation = conversation
            let schedule = PreProjectFoldersSchema.ScheduledTask()
            schedule.id = "saved-schedule"
            schedule.project = project
            schedule.workspaceKindRawValue = "project"
            schedule.grantedRoots = ["/missing/schedule-grant"]
            let run = PreProjectFoldersSchema.ScheduledTaskRun()
            run.id = "saved-run"
            run.projectPathSnapshot = "/original/run-source"
            run.grantedRootsSnapshot = ["/original/run-grant"]
            run.pendingWorktreeCleanupPath = "/original/cleanup"
            run.scheduledTask = schedule
            run.thread = thread
            context.insert(project)
            context.insert(thread)
            context.insert(conversation)
            context.insert(event)
            context.insert(schedule)
            context.insert(run)
            try context.save()
        }
    }
}
