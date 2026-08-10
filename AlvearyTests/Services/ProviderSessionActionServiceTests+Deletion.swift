import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// Delete routes a record to the provider, degrades to archive on failure, and reports what it could not clean up.
extension ProviderSessionActionServiceTests {
    func testDeletesMatchingProviderRecords() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        let deletedSessionIDs = await state.deletedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(deletedSessionIDs, ["session-1"])
    }

    func testDeleteFallsBackToArchiveWhenProviderDeleteFails() async throws {
        let state = ProviderActionAdapterState(failingDeleteSessionIDs: ["session-1"])
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        let archivedSessionIDs = await state.archivedSessionIDs
        let deletedSessionIDs = await state.deletedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(deletedSessionIDs, [])
        XCTAssertEqual(archivedSessionIDs, ["session-1"])
    }

    func testDeleteReportsConversationsWithNoResolvableSession() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        XCTAssertEqual(resolution.records, [])
        XCTAssertEqual(diagnostics.map(\.action), [.delete])
        XCTAssertEqual(diagnostics.map(\.conversationID), ["main"])
        XCTAssertEqual(diagnostics.map(\.message), ["No provider session binding is available."])
    }

    /// A thread whose first spawn failed never bound a provider session, so the unresolved binding
    /// is not something to warn about — deleting it should be silent.
    func testDeleteStaysSilentForConversationsWhoseThreadNeverStarted() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversations: [
                ProviderSessionConversationSnapshot(
                    conversationID: "main",
                    providerID: "codex",
                    hasStartedProviderSession: false
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        XCTAssertEqual(resolution.records, [])
        XCTAssertEqual(resolution.missingBindings, [])
        XCTAssertEqual(diagnostics, [])
    }

    func testDeleteSkipsProvidersWithoutNativeDeletion() async throws {
        let state = ProviderActionAdapterState()
        let service = try await makeService(
            store: AgentCLIKit.InMemoryAgentSessionStore(records: [
                sessionRecord(conversationId: "main", providerId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ]),
            state: state,
            capabilities: AgentCLIKit.AgentProviderCapabilities()
        )

        let resolution = await service.resolveSessions(matching: ProviderSessionActionSnapshot(
            conversationIDs: ["main"],
            providerIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        let deletedSessionIDs = await state.deletedSessionIDs
        let archivedSessionIDs = await state.archivedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(deletedSessionIDs, [])
        XCTAssertEqual(archivedSessionIDs, [])
    }
}
