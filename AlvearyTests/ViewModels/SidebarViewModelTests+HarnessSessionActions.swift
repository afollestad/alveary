import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchiveThreadCallsHarnessCompanionAction() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            hasCompletedInitialSetup: true,
            archivedAt: nil,
            harness: "codex"
        )

        try await fixture.viewModel.archiveThread(thread)

        let actions = await fixture.harnessSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(HarnessSessionActionSnapshot(
                conversationIDs: ["main"],
                harnessIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            )),
            .archive(HarnessSessionActionSnapshot(
                conversationIDs: ["main"],
                harnessIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            ))
        ])
    }

    func testArchiveThreadBackfillsHarnessSessionBindingFromLiveRecordBeforeTeardown() async throws {
        let record = harnessSessionRecord(
            conversationId: "main",
            harnessId: .codex,
            sessionId: "codex-thread",
            workingDirectory: "/tmp/alveary-project"
        )
        let fixture = try SidebarTestFixture(
            harnessSessionActions: RecordingHarnessSessionActionService(resolvedRecords: [record])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: nil,
            harness: "codex"
        )

        try await fixture.viewModel.archiveThread(thread)

        let conversation = try fixture.requireConversation(id: "main")
        XCTAssertEqual(conversation.harnessSessionId, "codex-thread")
        XCTAssertEqual(conversation.harnessSessionHarnessId, "codex")
        XCTAssertEqual(conversation.harnessSessionWorkingDirectory, "/tmp/alveary-project")
    }

    func testArchiveThreadHarnessCompanionFailureSurfacesUnexpectedErrorWithoutRollingBackLocalArchive() async throws {
        let diagnostic = HarnessSessionActionDiagnostic.fixture(action: .archive)
        let fixture = try SidebarTestFixture(
            harnessSessionActions: RecordingHarnessSessionActionService(archiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: nil,
            harness: "codex"
        )

        try await fixture.viewModel.archiveThread(thread)

        let archivedThread = try fixture.requireThread(thread)
        XCTAssertNotNil(archivedThread.archivedAt)
        XCTAssertEqual(fixture.unexpectedErrors.messages, [diagnostic.toastMessage])
    }

    func testDeleteThreadCallsHarnessCompanionDeleteAction() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            hasCompletedInitialSetup: true,
            harness: "codex",
            harnessSessionId: "codex-thread",
            harnessSessionHarnessId: "codex",
            harnessSessionWorkingDirectory: "/tmp/alveary-project"
        )

        try await fixture.viewModel.deleteThread(thread)

        let snapshot = HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: "main",
                    harnessID: "codex",
                    harnessSessionID: "codex-thread",
                    harnessSessionHarnessID: "codex",
                    harnessSessionWorkingDirectory: "/tmp/alveary-project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
        )
        let actions = await fixture.harnessSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(snapshot),
            .delete(snapshot)
        ])
    }

    /// The snapshot has to carry the thread's started state, or the service cannot tell a failed first spawn's
    /// phantom binding from a real one worth reporting.
    func testDeleteThreadReportsNeverStartedThreadInHarnessSessionSnapshot() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            hasCompletedInitialSetup: false,
            harness: "codex"
        )

        try await fixture.viewModel.deleteThread(thread)

        let snapshot = HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: "main",
                    harnessID: "codex",
                    hasStartedHarnessSession: false
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
        )
        let actions = await fixture.harnessSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(snapshot),
            .delete(snapshot)
        ])
    }

    /// A conversation whose harness session cannot be resolved leaves a live harness-side session behind, so the
    /// delete path forwards it for the service to report rather than deleting the thread in silence.
    func testDeleteThreadForwardsMissingHarnessSessionBinding() async throws {
        let missingBinding = HarnessSessionActionMissingBinding(
            conversationID: "main",
            harnessID: .codex
        )
        let fixture = try SidebarTestFixture(
            harnessSessionActions: RecordingHarnessSessionActionService(resolvedMissingBindings: [missingBinding])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            harness: "codex"
        )

        try await fixture.viewModel.deleteThread(thread)

        let deletedMissingBindings = await fixture.harnessSessionActions.deletedMissingBindings
        XCTAssertEqual(deletedMissingBindings, [missingBinding])
        XCTAssertEqual(fixture.unexpectedErrors.messages, [])
    }

    func testDeleteThreadHarnessCompanionFailureSurfacesUnexpectedErrorWithoutRollingBackLocalDelete() async throws {
        let diagnostic = HarnessSessionActionDiagnostic.fixture(action: .delete)
        let fixture = try SidebarTestFixture(
            harnessSessionActions: RecordingHarnessSessionActionService(deleteDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            harness: "codex",
            harnessSessionId: "codex-thread",
            harnessSessionHarnessId: "codex",
            harnessSessionWorkingDirectory: "/tmp/alveary-project"
        )

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertFalse(try fixture.threadExists(thread))
        XCTAssertEqual(fixture.unexpectedErrors.messages, [diagnostic.toastMessage])
    }

    func testDeleteThreadHarnessCompanionRunsWhenRuntimeTeardownFails() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            harness: "codex",
            harnessSessionId: "codex-thread",
            harnessSessionHarnessId: "codex",
            harnessSessionWorkingDirectory: "/tmp/alveary-project"
        )
        await fixture.agentsManager.setDestroyError(.destroyFailed("main"), for: "main")

        do {
            try await fixture.viewModel.deleteThread(thread)
            XCTFail("Expected delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .threadDeleteCleanupFailed = error else {
                XCTFail("Expected thread delete cleanup failure")
                return
            }
        }

        let actions = await fixture.harnessSessionActions.actions
        XCTAssertEqual(actions.map {
            if case .delete = $0 { return "delete" }
            if case .resolve = $0 { return "resolve" }
            return "other"
        }, ["resolve", "delete"])
        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testRestoreThreadCallsHarnessCompanionAction() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            hasCompletedInitialSetup: true,
            archivedAt: Date(),
            harness: "codex"
        )

        try await fixture.viewModel.restoreThread(thread)

        let actions = await fixture.harnessSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(HarnessSessionActionSnapshot(
                conversationIDs: ["main"],
                harnessIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            )),
            .unarchive(HarnessSessionActionSnapshot(
                conversationIDs: ["main"],
                harnessIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            ))
        ])
    }

    func testRestoreThreadUsesPersistedHarnessSessionBindingAfterLiveRecordIsGone() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            hasCompletedInitialSetup: true,
            archivedAt: Date(),
            harness: "codex",
            harnessSessionId: "codex-thread",
            harnessSessionHarnessId: "codex",
            harnessSessionWorkingDirectory: "/tmp/archived-project"
        )
        let snapshot = HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: "main",
                    harnessID: "codex",
                    harnessSessionID: "codex-thread",
                    harnessSessionHarnessID: "codex",
                    harnessSessionWorkingDirectory: "/tmp/archived-project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
        )

        try await fixture.viewModel.restoreThread(thread)

        let actions = await fixture.harnessSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(snapshot),
            .unarchive(snapshot)
        ])
    }

    func testRestoreThreadHarnessCompanionFailureSurfacesUnexpectedErrorWithoutRollingBackLocalRestore() async throws {
        let diagnostic = HarnessSessionActionDiagnostic.fixture(action: .unarchive)
        let fixture = try SidebarTestFixture(
            harnessSessionActions: RecordingHarnessSessionActionService(unarchiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date(),
            harness: "codex"
        )

        try await fixture.viewModel.restoreThread(thread)

        let restoredThread = try fixture.requireThread(thread)
        XCTAssertNil(restoredThread.archivedAt)
        XCTAssertEqual(fixture.unexpectedErrors.messages, [diagnostic.toastMessage])
    }

    func testDeleteProjectDeletesUniqueChildHarnessSessionsBeforeCleanupFailure() async throws {
        let fixture = try SidebarTestFixture(
            harnessSessionActions: RecordingHarnessSessionActionService(
                resolvedRecords: deleteProjectHarnessSessionRecords()
            )
        )
        // The cleanup failure under test only happens once Git cleanup actually runs, which needs
        // the project folder present.
        let projectDirectory = try SidebarTestProjectDirectory(name: "delete-project-sessions")
        defer { projectDirectory.remove() }
        let project = try insertDeleteProjectHarnessSessionFixture(
            into: fixture,
            projectPath: projectDirectory.path
        )
        await fixture.worktreeManager.setRemoveError(.removeFailed)

        do {
            try await fixture.viewModel.deleteProject(project)
            XCTFail("Expected project delete to throw")
        } catch let error as SidebarViewModelError {
            guard case .projectDeleteCleanupFailed = error else {
                XCTFail("Expected project delete cleanup failure")
                return
            }
        }

        let deletedRecords = await fixture.harnessSessionActions.deletedRecords
        XCTAssertEqual(deletedRecords.map(\.harnessSessionId), ["codex-thread", "other-codex-thread"])
    }
}

@MainActor
private func insertDeleteProjectHarnessSessionFixture(
    into fixture: SidebarTestFixture,
    projectPath: String
) throws -> Project {
    let project = Project(path: projectPath, name: "Alveary")
    let primaryThread = AgentThread(
        name: "Primary",
        branch: "alveary/live",
        worktreePath: "/tmp/alveary-worktree",
        hasCompletedInitialSetup: true,
        useWorktree: true,
        project: project
    )
    primaryThread.conversations = [
        Conversation(id: "main", title: "Main", harness: "codex", isMain: true, displayOrder: 0, thread: primaryThread),
        Conversation(id: "side", title: "Side", harness: "codex", isMain: false, displayOrder: 1, thread: primaryThread)
    ]
    let secondaryThread = AgentThread(name: "Secondary", project: project)
    secondaryThread.conversations = [
        Conversation(id: "other", title: "Other", harness: "codex", isMain: true, displayOrder: 0, thread: secondaryThread)
    ]
    project.threads = [primaryThread, secondaryThread]
    fixture.context.insert(project)
    try fixture.context.save()
    return project
}

private func deleteProjectHarnessSessionRecords() -> [AgentCLIKit.AgentSessionRecord] {
    [
        harnessSessionRecord(conversationId: "main", harnessId: .codex, sessionId: "codex-thread", workingDirectory: "/tmp/alveary-project"),
        harnessSessionRecord(conversationId: "side", harnessId: .codex, sessionId: "codex-thread", workingDirectory: "/tmp/alveary-project"),
        harnessSessionRecord(conversationId: "other", harnessId: .codex, sessionId: "other-codex-thread", workingDirectory: "/tmp/alveary-project")
    ]
}

private func harnessSessionRecord(
    conversationId: AgentCLIKit.AgentConversationID,
    harnessId: AgentCLIKit.AgentHarnessID,
    sessionId: AgentCLIKit.AgentSessionID,
    workingDirectory: String
) -> AgentCLIKit.AgentSessionRecord {
    AgentCLIKit.AgentSessionRecord(
        conversationId: conversationId,
        harnessId: harnessId,
        harnessSessionId: sessionId,
        workingDirectory: URL(fileURLWithPath: workingDirectory, isDirectory: true),
        generation: 0,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
