import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testDeletionSaveFailureKeepsTargetAndPersistsUnrelatedPendingChange() async throws {
        let fixture = try SidebarTestFixture(saveDeletionCommit: { _ in
            throw SidebarDeletionCommitTestError.saveFailed
        })
        let thread = try fixture.insertThread(
            projectName: "Deleted target",
            projectPath: "/tmp/deletion-save-target",
            conversationIDs: ["main"]
        )
        let unrelatedProject = try fixture.insertProject(
            name: "Original name",
            path: "/tmp/deletion-save-unrelated"
        )
        unrelatedProject.name = "Persisted pending name"

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected deletion commit to fail")
        } catch SidebarDeletionCommitTestError.saveFailed {
            // expected
        }

        XCTAssertNotNil(fixture.context.resolveThread(id: thread.persistentModelID))
        let verificationContext = ModelContext(fixture.container)
        let unrelatedPath = unrelatedProject.path
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == unrelatedPath
        })
        XCTAssertEqual(try verificationContext.fetch(descriptor).first?.name, "Persisted pending name")
        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertTrue(removedConversationIDs.isEmpty)
    }

    func testDeleteThreadRemovesEveryConversationAttachmentDirectory() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-attachment-cleanup",
            conversationIDs: ["main", "side"]
        )

        try await fixture.viewModel.deleteThread(thread)

        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs.sorted(), ["main", "side"])
    }

    func testDeleteProjectRemovesAttachmentDirectoriesAcrossAllThreads() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project-attachment-cleanup", name: "Alveary")
        let first = AgentThread(name: "First", project: project)
        first.conversations = [
            Conversation(id: "first", provider: "claude", isMain: true, displayOrder: 0, thread: first)
        ]
        let second = AgentThread(name: "Second", project: project)
        second.conversations = [
            Conversation(id: "second", provider: "claude", isMain: true, displayOrder: 0, thread: second)
        ]
        project.threads = [first, second]
        fixture.context.insert(project)
        try fixture.context.save()

        try await fixture.viewModel.deleteProject(project)

        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs.sorted(), ["first", "second"])
    }

    func testTrustEquivalentDraftDeleteCannotReuseOldDraftOrDestroyReplacementRuntime() async throws {
        let providerSessionActions = RecordingProviderSessionActionService(pausesResolution: true)
        let fixture = try SidebarTestFixture(providerSessionActions: providerSessionActions)
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/draft-delete-race")
        let oldDraft = try await fixture.viewModel.openDraftThread(project: project)
        let oldThreadID = oldDraft.persistentModelID
        let oldConversationID = try XCTUnwrap(oldDraft.conversations.first?.id)

        let deletion = Task { @MainActor in
            try await fixture.viewModel.deleteThread(oldDraft)
        }
        await providerSessionActions.waitUntilResolutionBegins()
        defer { Task { await providerSessionActions.resumeResolution() } }

        XCTAssertNil(fixture.context.resolveThread(id: oldThreadID))
        let replacement = try await fixture.viewModel.openDraftThread(project: project)
        let replacementID = replacement.persistentModelID
        let replacementConversationID = try XCTUnwrap(replacement.conversations.first?.id)
        replacement.isDraft = false
        try fixture.context.save()

        await providerSessionActions.resumeResolution()
        try await deletion.value

        XCTAssertNotEqual(replacementID, oldThreadID)
        XCTAssertNotNil(fixture.context.resolveThread(id: replacementID))
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls, [oldConversationID])
        XCTAssertNotEqual(replacementConversationID, oldConversationID)
    }

    func testProjectDeleteRejectsStaleProjectWhileCleanupIsInFlightAndPreservesOtherDraft() async throws {
        let providerSessionActions = RecordingProviderSessionActionService(pausesResolution: true)
        let fixture = try SidebarTestFixture(providerSessionActions: providerSessionActions)
        let deletedProject = try fixture.insertProject(name: "Deleted", path: "/tmp/draft-project-delete-race")
        let deletedProjectID = deletedProject.persistentModelID
        let oldDraft = try await fixture.viewModel.openDraftThread(project: deletedProject)
        let oldConversationID = try XCTUnwrap(oldDraft.conversations.first?.id)

        let deletion = Task { @MainActor in
            try await fixture.viewModel.deleteProject(deletedProject)
        }
        await providerSessionActions.waitUntilResolutionBegins()
        defer { Task { await providerSessionActions.resumeResolution() } }

        XCTAssertNil(fixture.context.resolveProject(id: deletedProjectID))
        do {
            _ = try await fixture.viewModel.openDraftThread(project: deletedProject)
            XCTFail("Expected the deleting project to remain unavailable")
        } catch SidebarViewModelError.projectMissing {
            // expected
        }

        let survivingProject = try fixture.insertProject(name: "Surviving", path: "/tmp/draft-project-surviving")
        let survivingDraft = try await fixture.viewModel.openDraftThread(project: survivingProject)
        let survivingID = survivingDraft.persistentModelID
        survivingDraft.isDraft = false
        try fixture.context.save()

        await providerSessionActions.resumeResolution()
        try await deletion.value

        XCTAssertNotNil(fixture.context.resolveThread(id: survivingID))
        let destroyCalls = await fixture.agentsManager.destroyCalls()
        XCTAssertEqual(destroyCalls, [oldConversationID])
    }

    func testDeleteThreadDeletesModelBeforeReportingRuntimeCleanupFailure() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"]
        )
        await fixture.agentsManager.setDestroyError(.destroyFailed("main"), for: "main")

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockAgentsManager.MockError else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .destroyFailed("main"))
        }

        XCTAssertFalse(try fixture.threadExists(thread))
        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs, ["main"])
    }

    func testDeleteThreadKeepsModelDeletedWhenWorktreeCleanupFails() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            branch: "alveary/live",
            worktreePath: "/tmp/alveary-worktree",
            hasCompletedInitialSetup: true,
            useWorktree: true
        )
        await fixture.worktreeManager.setRemoveError(.removeFailed)

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockWorktreeManager.MockError else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .removeFailed)
        }

        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testDeleteProjectKeepsModelDeletedWhenFinalWorktreeSweepFails() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(path: "/tmp/alveary-project", name: "Alveary")
        let thread = AgentThread(name: "Primary", project: project)
        thread.conversations = [
            Conversation(id: "main", title: "Main", provider: "claude", isMain: true, displayOrder: 0, thread: thread)
        ]

        project.threads = [thread]
        fixture.context.insert(project)
        try fixture.context.save()
        await fixture.worktreeManager.setRemoveAllError(.removeAllFailed)

        do {
            try await fixture.viewModel.deleteProject(project)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .projectDeleteCleanupFailed(let underlying) = error,
                  let mockError = underlying as? SidebarMockWorktreeManager.MockError else {
                XCTFail("Expected project delete cleanup failure")
                return
            }
            XCTAssertEqual(mockError, .removeAllFailed)
        }

        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Project>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 0)
        let removedConversationIDs = await fixture.attachmentStore.removedConversationIDs
        XCTAssertEqual(removedConversationIDs, ["main"])
    }
}

private enum SidebarDeletionCommitTestError: Error {
    case saveFailed
}
