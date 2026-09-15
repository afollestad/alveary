import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

/// Delete routes a record to the harness, degrades to archive on failure, and reports what it could not clean up.
extension HarnessSessionActionServiceTests {
    func testDeletesMatchingHarnessRecords() async throws {
        let state = HarnessActionAdapterState()
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", harnessId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        let deletedSessionIDs = await state.deletedSessionIDs

        XCTAssertEqual(diagnostics, [])
        XCTAssertEqual(deletedSessionIDs, ["session-1"])
    }

    func testDeleteFallsBackToArchiveWhenHarnessDeleteFails() async throws {
        let state = HarnessActionAdapterState(failingDeleteSessionIDs: ["session-1"])
        let service = try await makeService(
            records: [
                sessionRecord(conversationId: "main", harnessId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ],
            state: state
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["codex"],
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
        let state = HarnessActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["codex"],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        XCTAssertEqual(resolution.records, [])
        XCTAssertEqual(diagnostics.map(\.action), [.delete])
        XCTAssertEqual(diagnostics.map(\.conversationID), ["main"])
        XCTAssertEqual(diagnostics.map(\.message), ["No harness session binding is available."])
    }

    /// A thread whose first spawn failed never bound a harness session, so the unresolved binding
    /// is not something to warn about — deleting it should be silent.
    func testDeleteStaysSilentForConversationsWhoseThreadNeverStarted() async throws {
        let state = HarnessActionAdapterState()
        let service = try await makeService(records: [], state: state)

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversations: [
                HarnessSessionConversationSnapshot(
                    conversationID: "main",
                    harnessID: "codex",
                    hasStartedHarnessSession: false
                )
            ],
            workingDirectory: URL(fileURLWithPath: "/tmp/project", isDirectory: true)
        ))
        let diagnostics = await service.deleteSessions(resolution)

        XCTAssertEqual(resolution.records, [])
        XCTAssertEqual(resolution.missingBindings, [])
        XCTAssertEqual(diagnostics, [])
    }

    func testDeleteSkipsHarnessesWithoutNativeDeletion() async throws {
        let state = HarnessActionAdapterState()
        let service = try await makeService(
            store: AgentCLIKit.InMemoryAgentSessionStore(records: [
                sessionRecord(conversationId: "main", harnessId: .codex, sessionId: "session-1", workingDirectory: "/tmp/project")
            ]),
            state: state,
            capabilities: AgentCLIKit.AgentHarnessCapabilities()
        )

        let resolution = await service.resolveSessions(matching: HarnessSessionActionSnapshot(
            conversationIDs: ["main"],
            harnessIDs: ["codex"],
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
