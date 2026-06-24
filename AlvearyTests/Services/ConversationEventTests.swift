import XCTest

@testable import Alveary

@MainActor
final class ConversationEventTests: XCTestCase {
    func testSteeredConversationToRecordPersistsDeterministicMarker() throws {
        let conversation = Conversation(provider: "codex")

        let record = try XCTUnwrap(
            ConversationEvent.steeredConversation(inputID: "local-user-1")
                .toRecord(conversation: conversation)
        )

        XCTAssertEqual(record.id, "steering-local-user-1")
        XCTAssertEqual(record.type, ConversationEventRecord.steeredConversationType)
        XCTAssertEqual(record.content, ConversationSteering.displayMessage)
        XCTAssertEqual(record.conversationId, conversation.id)
        XCTAssertEqual(record.conversation?.id, conversation.id)
    }

    func testTaskListSnapshotToRecordPersistsJSONPayload() throws {
        let conversation = Conversation(provider: "codex")
        let snapshot = ConversationTaskListSnapshot(
            id: "tasks-codex-plan-turn-1",
            items: [
                ConversationTaskListItem(id: "task-1", content: "Inspect", status: .completed),
                ConversationTaskListItem(
                    id: "task-2",
                    content: "Implement",
                    activeForm: "Implementing",
                    status: .inProgress
                ),
                ConversationTaskListItem(id: "task-3", content: "Verify", status: .interrupted)
            ]
        )
        let record = try XCTUnwrap(ConversationEvent.taskListSnapshot(snapshot).toRecord(conversation: conversation))

        XCTAssertEqual(record.type, ConversationEventRecord.taskListType)
        XCTAssertEqual(record.conversationId, conversation.id)
        XCTAssertEqual(record.conversation?.id, conversation.id)

        let decoded = try XCTUnwrap(ConversationTaskListSnapshot.decoded(from: record))
        XCTAssertEqual(decoded, snapshot)

        let legacyPayload = """
        {
          "id": "tasks-legacy",
          "items": [
            { "id": "task-1", "content": "Legacy in progress", "status": "inProgress" },
            { "id": "task-2", "content": "Unknown status", "status": "blocked" },
            { "id": "task-3", "content": "Missing status" },
            { "id": "task-4", "content": "Interrupted status", "status": "interrupted" },
            { "id": "task-5", "content": "Canceled status", "status": "canceled" },
            { "id": "task-6", "content": "Cancelled status", "status": "cancelled" }
          ]
        }
        """
        let legacyData = try XCTUnwrap(legacyPayload.data(using: .utf8))
        let legacySnapshot = try JSONDecoder().decode(ConversationTaskListSnapshot.self, from: legacyData)
        XCTAssertEqual(legacySnapshot.items.map(\.status), [
            .inProgress,
            .pending,
            .pending,
            .interrupted,
            .interrupted,
            .interrupted
        ])
    }

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
        XCTAssertTrue(tokensRecord.costUsdReported)
        XCTAssertEqual(tokensRecord.providerModelId, "claude-sonnet-4-6")
        XCTAssertEqual(tokensRecord.contextWindowSize, 200_000)

        XCTAssertEqual(sessionInitRecord.type, "session_init")
        XCTAssertEqual(sessionInitRecord.content, "session-1")
    }

    func testMissingTokenCostPersistsZeroWithoutReportedFlag() throws {
        let conversation = Conversation(provider: "codex")
        let tokensRecord = try XCTUnwrap(
            ConversationEvent.tokens(
                input: 10,
                output: 20,
                cacheRead: 5,
                isError: false,
                stopReason: ConversationEvent.interimUsageStopReason,
                durationMs: 0,
                costUsd: nil,
                permissionDenials: []
            ).toRecord(conversation: conversation)
        )

        XCTAssertEqual(tokensRecord.costUsd, 0)
        XCTAssertFalse(tokensRecord.costUsdReported)
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

    func testContextCompactionEventsProducePersistedRecords() throws {
        let conversation = Conversation(provider: "claude")

        let started = try XCTUnwrap(
            ConversationEvent.contextCompactionStarted(id: "compact-1", trigger: "auto")
                .toRecord(conversation: conversation)
        )
        let completed = try XCTUnwrap(
            ConversationEvent.contextCompactionCompleted(id: "compact-1", summary: "Reduced history")
                .toRecord(conversation: conversation)
        )
        let failed = try XCTUnwrap(
            ConversationEvent.contextCompactionFailed(id: "compact-2", error: "Compaction failed")
                .toRecord(conversation: conversation)
        )

        XCTAssertEqual(started.type, ConversationContextCompaction.startedType)
        XCTAssertEqual(started.toolId, "compact-1")
        XCTAssertEqual(started.content, "auto")
        XCTAssertFalse(started.isError)

        XCTAssertEqual(completed.type, ConversationContextCompaction.completedType)
        XCTAssertEqual(completed.toolId, "compact-1")
        XCTAssertEqual(completed.content, "Reduced history")

        XCTAssertEqual(failed.type, ConversationContextCompaction.failedType)
        XCTAssertEqual(failed.toolId, "compact-2")
        XCTAssertEqual(failed.content, "Compaction failed")
        XCTAssertTrue(failed.isError)
    }

    func testStreamOnlyEventsDoNotCreateRecords() {
        let conversation = Conversation(provider: "claude")

        XCTAssertNil(ConversationEvent.messageChunk(text: "chunk", parentToolUseId: nil).toRecord(conversation: conversation))
        XCTAssertNil(ConversationEvent.thinking(content: "thinking", parentToolUseId: nil).toRecord(conversation: conversation))
        XCTAssertNil(
            ConversationEvent.subAgentStarted(toolUseId: "tool-1", description: "Plan", taskType: nil)
                .toRecord(conversation: conversation)
        )
        XCTAssertNil(
            ConversationEvent.subAgentCompleted(toolUseId: "tool-1", status: "completed", toolUses: 1, totalTokens: 50, durationMs: 250)
                .toRecord(conversation: conversation)
        )
        XCTAssertNil(
            ConversationEvent.runtimeActivity(state: .idle, turnId: "turn-1", outcome: .completed)
                .toRecord(conversation: conversation)
        )
        XCTAssertNil(
            ConversationEvent.providerSessionMetadataChanged(sessionId: "thread-1", name: "Generated", preview: "Preview")
                .toRecord(conversation: conversation)
        )
    }
}
