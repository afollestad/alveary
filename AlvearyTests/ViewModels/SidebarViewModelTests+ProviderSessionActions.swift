import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchiveThreadCallsProviderCompanionAction() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: nil,
            provider: "codex"
        )

        try await fixture.viewModel.archiveThread(thread)

        let actions = await fixture.providerSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(ProviderSessionActionSnapshot(
                conversationIDs: ["main"],
                providerIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            )),
            .archive(ProviderSessionActionSnapshot(
                conversationIDs: ["main"],
                providerIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            ))
        ])
    }

    func testArchiveThreadBackfillsProviderSessionBindingFromLiveRecordBeforeTeardown() async throws {
        let record = providerSessionRecord(
            conversationId: "main",
            providerId: .codex,
            sessionId: "codex-thread",
            workingDirectory: "/tmp/alveary-project"
        )
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(resolvedRecords: [record])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: nil,
            provider: "codex"
        )

        try await fixture.viewModel.archiveThread(thread)

        let conversation = try fixture.requireConversation(id: "main")
        XCTAssertEqual(conversation.providerSessionId, "codex-thread")
        XCTAssertEqual(conversation.providerSessionProviderId, "codex")
        XCTAssertEqual(conversation.providerSessionWorkingDirectory, "/tmp/alveary-project")
    }

    func testArchiveThreadProviderCompanionFailureSurfacesUnexpectedErrorWithoutRollingBackLocalArchive() async throws {
        let diagnostic = ProviderSessionActionDiagnostic.fixture(action: .archive)
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(archiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: nil,
            provider: "codex"
        )

        try await fixture.viewModel.archiveThread(thread)

        let archivedThread = try fixture.requireThread(thread)
        XCTAssertNotNil(archivedThread.archivedAt)
        XCTAssertEqual(fixture.unexpectedErrors.messages, [diagnostic.toastMessage])
    }

    func testDeleteThreadCallsProviderCompanionArchiveAction() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            provider: "codex",
            providerSessionId: "codex-thread",
            providerSessionProviderId: "codex",
            providerSessionWorkingDirectory: "/tmp/alveary-project"
        )

        try await fixture.viewModel.deleteThread(thread)

        let snapshot = ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(
                    conversationID: "main",
                    providerID: "codex",
                    providerSessionID: "codex-thread",
                    providerSessionProviderID: "codex",
                    providerSessionWorkingDirectory: "/tmp/alveary-project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
        )
        let actions = await fixture.providerSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(snapshot),
            .archive(snapshot)
        ])
    }

    func testDeleteThreadDoesNotSurfaceMissingProviderSessionBinding() async throws {
        let missingBinding = ProviderSessionActionMissingBinding(
            conversationID: "main",
            providerID: .codex
        )
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(resolvedMissingBindings: [missingBinding])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            provider: "codex"
        )

        try await fixture.viewModel.deleteThread(thread)

        let archivedMissingBindings = await fixture.providerSessionActions.archivedMissingBindings
        XCTAssertEqual(archivedMissingBindings, [])
        XCTAssertEqual(fixture.unexpectedErrors.messages, [])
    }

    func testDeleteThreadProviderCompanionFailureSurfacesUnexpectedErrorWithoutRollingBackLocalDelete() async throws {
        let diagnostic = ProviderSessionActionDiagnostic.fixture(action: .archive)
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(archiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            provider: "codex",
            providerSessionId: "codex-thread",
            providerSessionProviderId: "codex",
            providerSessionWorkingDirectory: "/tmp/alveary-project"
        )

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertFalse(try fixture.threadExists(thread))
        XCTAssertEqual(fixture.unexpectedErrors.messages, [diagnostic.toastMessage])
    }

    func testDeleteThreadProviderCompanionRunsWhenRuntimeTeardownFails() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            provider: "codex",
            providerSessionId: "codex-thread",
            providerSessionProviderId: "codex",
            providerSessionWorkingDirectory: "/tmp/alveary-project"
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

        let actions = await fixture.providerSessionActions.actions
        XCTAssertEqual(actions.map {
            if case .archive = $0 { return "archive" }
            if case .resolve = $0 { return "resolve" }
            return "other"
        }, ["resolve", "archive"])
        XCTAssertFalse(try fixture.threadExists(thread))
    }

    func testRestoreThreadCallsProviderCompanionAction() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date(),
            provider: "codex"
        )

        try await fixture.viewModel.restoreThread(thread)

        let actions = await fixture.providerSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(ProviderSessionActionSnapshot(
                conversationIDs: ["main"],
                providerIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            )),
            .unarchive(ProviderSessionActionSnapshot(
                conversationIDs: ["main"],
                providerIDs: ["codex"],
                workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
            ))
        ])
    }

    func testRestoreThreadUsesPersistedProviderSessionBindingAfterLiveRecordIsGone() async throws {
        let fixture = try SidebarTestFixture()
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date(),
            provider: "codex",
            providerSessionId: "codex-thread",
            providerSessionProviderId: "codex",
            providerSessionWorkingDirectory: "/tmp/archived-project"
        )
        let snapshot = ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(
                    conversationID: "main",
                    providerID: "codex",
                    providerSessionID: "codex-thread",
                    providerSessionProviderID: "codex",
                    providerSessionWorkingDirectory: "/tmp/archived-project"
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/alveary-project", isDirectory: true)
        )

        try await fixture.viewModel.restoreThread(thread)

        let actions = await fixture.providerSessionActions.actions
        XCTAssertEqual(actions, [
            .resolve(snapshot),
            .unarchive(snapshot)
        ])
    }

    func testRestoreThreadProviderCompanionFailureSurfacesUnexpectedErrorWithoutRollingBackLocalRestore() async throws {
        let diagnostic = ProviderSessionActionDiagnostic.fixture(action: .unarchive)
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(unarchiveDiagnostics: [diagnostic])
        )
        let thread = try fixture.insertThread(
            projectName: "Alveary",
            projectPath: "/tmp/alveary-project",
            conversationIDs: ["main"],
            archivedAt: Date(),
            provider: "codex"
        )

        try await fixture.viewModel.restoreThread(thread)

        let restoredThread = try fixture.requireThread(thread)
        XCTAssertNil(restoredThread.archivedAt)
        XCTAssertEqual(fixture.unexpectedErrors.messages, [diagnostic.toastMessage])
    }

    func testDeleteProjectArchivesUniqueChildProviderSessionsBeforeCleanupFailure() async throws {
        let fixture = try SidebarTestFixture(
            providerSessionActions: RecordingProviderSessionActionService(
                resolvedRecords: deleteProjectProviderSessionRecords()
            )
        )
        let project = try insertDeleteProjectProviderSessionFixture(into: fixture)
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

        let archivedRecords = await fixture.providerSessionActions.archivedRecords
        XCTAssertEqual(archivedRecords.map(\.providerSessionId), ["codex-thread", "other-codex-thread"])
    }
}

@MainActor
private func insertDeleteProjectProviderSessionFixture(into fixture: SidebarTestFixture) throws -> Project {
    let project = Project(path: "/tmp/alveary-project", name: "Alveary")
    let primaryThread = AgentThread(
        name: "Primary",
        branch: "alveary/live",
        worktreePath: "/tmp/alveary-worktree",
        hasCompletedInitialSetup: true,
        useWorktree: true,
        project: project
    )
    primaryThread.conversations = [
        Conversation(id: "main", title: "Main", provider: "codex", isMain: true, displayOrder: 0, thread: primaryThread),
        Conversation(id: "side", title: "Side", provider: "codex", isMain: false, displayOrder: 1, thread: primaryThread)
    ]
    let secondaryThread = AgentThread(name: "Secondary", project: project)
    secondaryThread.conversations = [
        Conversation(id: "other", title: "Other", provider: "codex", isMain: true, displayOrder: 0, thread: secondaryThread)
    ]
    project.threads = [primaryThread, secondaryThread]
    fixture.context.insert(project)
    try fixture.context.save()
    return project
}

private func deleteProjectProviderSessionRecords() -> [AgentCLIKit.AgentSessionRecord] {
    [
        providerSessionRecord(conversationId: "main", providerId: .codex, sessionId: "codex-thread", workingDirectory: "/tmp/alveary-project"),
        providerSessionRecord(conversationId: "side", providerId: .codex, sessionId: "codex-thread", workingDirectory: "/tmp/alveary-project"),
        providerSessionRecord(conversationId: "other", providerId: .codex, sessionId: "other-codex-thread", workingDirectory: "/tmp/alveary-project")
    ]
}

private func providerSessionRecord(
    conversationId: AgentCLIKit.AgentConversationID,
    providerId: AgentCLIKit.AgentProviderID,
    sessionId: AgentCLIKit.AgentSessionID,
    workingDirectory: String
) -> AgentCLIKit.AgentSessionRecord {
    AgentCLIKit.AgentSessionRecord(
        conversationId: conversationId,
        providerId: providerId,
        providerSessionId: sessionId,
        workingDirectory: URL(fileURLWithPath: workingDirectory, isDirectory: true),
        generation: 0,
        createdAt: Date(timeIntervalSince1970: 0),
        updatedAt: Date(timeIntervalSince1970: 0)
    )
}
