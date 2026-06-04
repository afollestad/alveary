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
