import Foundation
import XCTest

@testable import Alveary

final class ClaudeApprovalPersistenceStoreTests: XCTestCase {
    func testRecordsAndMatchesSessionApproval() async throws {
        let supportDirectory = temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let store = DefaultClaudeApprovalPersistenceStore(supportDirectory: supportDirectory)
        let approval = sessionApproval()

        let firstRecord = await store.recordSessionApproval(approval)
        let duplicateRecord = await store.recordSessionApproval(approval)
        let allowsExactCommand = await store.allowsSessionApproval(matching: [
            sessionApproval(matchValue: "git status")
        ])
        let allowsDifferentCommand = await store.allowsSessionApproval(matching: [
            sessionApproval(matchValue: "git diff")
        ])

        XCTAssertEqual(firstRecord, SessionApprovalRecordResult(isEffective: true, wasInserted: true))
        XCTAssertEqual(duplicateRecord, SessionApprovalRecordResult(isEffective: true, wasInserted: false))
        XCTAssertTrue(allowsExactCommand)
        XCTAssertFalse(allowsDifferentCommand)
    }

    func testSelectionAndSessionApprovalsAreRemovedTogether() async throws {
        let supportDirectory = temporarySupportDirectory()
        defer { try? FileManager.default.removeItem(at: supportDirectory) }
        let store = DefaultClaudeApprovalPersistenceStore(supportDirectory: supportDirectory)
        _ = await store.recordSessionApproval(sessionApproval())
        await store.recordToolApprovalSelection(
            .sessionExact,
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-1"
        )
        let selection = await store.toolApprovalSelection(
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-1"
        )

        await store.removeSessionApprovals(providerId: "claude", conversationId: "conversation-1", sessionId: "session-1")
        let allowsAfterRemoval = await store.allowsSessionApproval(matching: [
            sessionApproval(matchValue: "git status")
        ])
        let selectionAfterRemoval = await store.toolApprovalSelection(
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-1"
        )

        XCTAssertEqual(selection, .sessionExact)
        XCTAssertFalse(allowsAfterRemoval)
        XCTAssertNil(selectionAfterRemoval)
    }

    private func sessionApproval(matchValue: String = "git status") -> AgentSessionApprovalGrant {
        AgentSessionApprovalGrant(
            providerId: "claude",
            conversationId: "conversation-1",
            sessionId: "session-1",
            matchKind: .bashExact,
            matchValue: matchValue
        )
    }

    private func temporarySupportDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudeApprovalPersistenceStoreTests-\(UUID().uuidString)", isDirectory: true)
    }
}
