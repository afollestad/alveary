import XCTest

@testable import Alveary

@MainActor
final class ConversationEventTests: XCTestCase {
    func testToolResultToRecordPersistsMetadataAndConversationLink() throws {
        let conversation = Conversation(provider: "claude")
        let event = ConversationEvent.toolResult(
            id: "tool-1",
            output: "Done",
            isError: true,
            parentToolUseId: "parent-1",
            metadata: ToolResultMetadata(
                stderr: "warning",
                interrupted: true,
                isImage: true,
                noOutputExpected: true
            )
        )

        let record = try XCTUnwrap(event.toRecord(conversation: conversation))

        XCTAssertEqual(record.type, "tool_result")
        XCTAssertEqual(record.toolId, "tool-1")
        XCTAssertEqual(record.toolOutput, "Done")
        XCTAssertEqual(record.toolOutputStderr, "warning")
        XCTAssertTrue(record.toolOutputInterrupted)
        XCTAssertTrue(record.toolOutputIsImage)
        XCTAssertTrue(record.toolOutputNoOutputExpected)
        XCTAssertTrue(record.isError)
        XCTAssertEqual(record.parentToolUseId, "parent-1")
        XCTAssertEqual(record.conversationId, conversation.id)
        XCTAssertEqual(record.conversation?.id, conversation.id)
    }

    func testTokensAndSessionInitProducePersistedRecords() throws {
        let conversation = Conversation(provider: "claude")
        let tokensRecord = try XCTUnwrap(
            ConversationEvent.tokens(
                input: 10,
                output: 20,
                cacheRead: 5,
                cacheCreation: 7,
                isError: false,
                stopReason: "end_turn",
                durationMs: 1200,
                costUsd: 0.42,
                providerModelId: "claude-sonnet-4-6",
                contextWindowSize: 200_000,
                permissionDenials: []
            ).toRecord(conversation: conversation)
        )
        let sessionInitRecord = try XCTUnwrap(
            ConversationEvent.sessionInit(sessionId: "session-1").toRecord(conversation: conversation)
        )

        XCTAssertEqual(tokensRecord.type, "tokens")
        XCTAssertEqual(tokensRecord.tokenInput, 10)
        XCTAssertEqual(tokensRecord.tokenOutput, 20)
        XCTAssertEqual(tokensRecord.tokenCacheRead, 5)
        XCTAssertEqual(tokensRecord.tokenCacheCreation, 7)
        XCTAssertEqual(tokensRecord.stopReason, "end_turn")
        XCTAssertEqual(tokensRecord.durationMs, 1200)
        XCTAssertEqual(tokensRecord.costUsd, 0.42)
        XCTAssertEqual(tokensRecord.providerModelId, "claude-sonnet-4-6")
        XCTAssertEqual(tokensRecord.contextWindowSize, 200_000)

        XCTAssertEqual(sessionInitRecord.type, "session_init")
        XCTAssertEqual(sessionInitRecord.content, "session-1")
    }

    func testOptionalMessageContentRemainsNilInPersistedRecords() throws {
        let conversation = Conversation(provider: "claude")

        let notificationRecord = try XCTUnwrap(
            ConversationEvent.notification(type: "status", message: nil).toRecord(conversation: conversation)
        )
        let stopRecord = try XCTUnwrap(
            ConversationEvent.stop(message: nil).toRecord(conversation: conversation)
        )
        let sessionInitRecord = try XCTUnwrap(
            ConversationEvent.sessionInit(sessionId: nil).toRecord(conversation: conversation)
        )

        XCTAssertNil(notificationRecord.content)
        XCTAssertNil(stopRecord.content)
        XCTAssertNil(sessionInitRecord.content)
    }

    func testStreamOnlyEventsDoNotCreateRecords() {
        let conversation = Conversation(provider: "claude")

        XCTAssertNil(ConversationEvent.messageChunk(text: "chunk", parentToolUseId: nil).toRecord(conversation: conversation))
        XCTAssertNil(
            ConversationEvent.subAgentStarted(toolUseId: "tool-1", description: "Plan", taskType: nil)
                .toRecord(conversation: conversation)
        )
        XCTAssertNil(
            ConversationEvent.subAgentCompleted(toolUseId: "tool-1", status: "completed", toolUses: 1, totalTokens: 50, durationMs: 250)
                .toRecord(conversation: conversation)
        )
    }
}
