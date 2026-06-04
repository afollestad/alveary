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
