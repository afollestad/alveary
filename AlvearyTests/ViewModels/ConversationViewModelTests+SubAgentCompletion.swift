import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSubAgentCompletionPersistsHiddenMarkerOnce() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.handleEvent(.subAgentCompleted(
            toolUseId: "agent-1",
            status: "completed",
            toolUses: 2,
            totalTokens: 300,
            durationMs: 400
        ))
        fixture.viewModel.handleEvent(.subAgentCompleted(
            toolUseId: "agent-1",
            status: "completed",
            toolUses: 2,
            totalTokens: 300,
            durationMs: 400
        ))

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.type == ConversationEventRecord.subAgentCompletedType
        }
        XCTAssertEqual(records.count, 1)
        let record = try XCTUnwrap(records.first)
        XCTAssertEqual(record.id, "sub-agent-completed:\(fixture.conversation.id):agent-1")
        XCTAssertEqual(record.toolId, "agent-1")
        XCTAssertEqual(record.durationMs, 400)
        let content = try XCTUnwrap(record.content?.data(using: .utf8))
        let payload = try JSONDecoder().decode(SubAgentCompletionMarkerPayload.self, from: content)
        XCTAssertEqual(payload.status, "completed")
        XCTAssertEqual(payload.toolUses, 2)
        XCTAssertEqual(payload.totalTokens, 300)
    }
}
