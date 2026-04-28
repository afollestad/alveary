import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testHydratesPendingApprovalFromUnresolvedRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Edit",
            toolInput: "{\"file_path\":\"Sources/Auth.swift\"}",
            conversation: conversation
        )
        fixture.context.insert(record)
        try fixture.context.save()

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolUseId, "tool-1")
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolName, "Edit")
    }

    func testDoesNotHydratePendingApprovalFromResolvedApprovalRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let record = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Edit",
            toolInput: "{\"file_path\":\"Sources/Auth.swift\"}",
            toolApprovalStatus: ToolApprovalStatus.approved.rawValue,
            conversation: conversation
        )
        fixture.context.insert(record)
        try fixture.context.save()

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
    }

    func testHydratesLatestUnresolvedApprovalWhenNewerResolvedRecordExists() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let unresolvedRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-unresolved",
            toolName: "Bash",
            toolInput: "{\"command\":\"pwd\"}",
            timestamp: Date(timeIntervalSince1970: 1),
            conversation: conversation
        )
        let resolvedRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-resolved",
            toolName: "Bash",
            toolInput: "{\"command\":\"date\"}",
            toolApprovalStatus: ToolApprovalStatus.approved.rawValue,
            timestamp: Date(timeIntervalSince1970: 2),
            conversation: conversation
        )
        fixture.context.insert(unresolvedRecord)
        fixture.context.insert(resolvedRecord)
        try fixture.context.save()

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolUseId, "tool-unresolved")
    }

    func testDoesNotHydratePendingApprovalAfterDenyResolvesWithLaterToken() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approvalTime = Date()
        let approval = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}",
            timestamp: approvalTime,
            conversation: conversation
        )
        let resolvedToken = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tokens",
            stopReason: "end_turn",
            timestamp: approvalTime.addingTimeInterval(1),
            conversation: conversation
        )
        fixture.context.insert(approval)
        fixture.context.insert(resolvedToken)
        try fixture.context.save()

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
    }

    func testHydratesPendingApprovalWhenOnlyDeferredTokenExistsAfterApproval() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approvalTime = Date()
        let approval = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}",
            timestamp: approvalTime,
            conversation: conversation
        )
        let deferredToken = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tokens",
            stopReason: "tool_deferred",
            timestamp: approvalTime.addingTimeInterval(1),
            conversation: conversation
        )
        fixture.context.insert(approval)
        fixture.context.insert(deferredToken)
        try fixture.context.save()

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolUseId, "tool-1")
    }

    func testHydratesPendingApprovalWhenLaterTokenHasNoStopReason() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approvalTime = Date()
        let approval = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}",
            timestamp: approvalTime,
            conversation: conversation
        )
        let incompleteToken = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tokens",
            timestamp: approvalTime.addingTimeInterval(1),
            conversation: conversation
        )
        fixture.context.insert(approval)
        fixture.context.insert(incompleteToken)
        try fixture.context.save()

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolUseId, "tool-1")
    }

    func testHydratesPendingApprovalWhenLaterTokenIsInterimUsageUpdate() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approvalTime = Date()
        let approval = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: "session-123",
            toolId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}",
            timestamp: approvalTime,
            conversation: conversation
        )
        let usageUpdate = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tokens",
            stopReason: ConversationEvent.interimUsageStopReason,
            timestamp: approvalTime.addingTimeInterval(1),
            conversation: conversation
        )
        fixture.context.insert(approval)
        fixture.context.insert(usageUpdate)
        try fixture.context.save()

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request.toolUseId, "tool-1")
    }

    func testHydrateMarksApprovalResolvedWhenClaudeSessionAlreadyConsumedIt() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let sessionId = "session-restored"
        let toolUseId = "tool-restored"
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: sessionId,
            toolId: toolUseId,
            toolName: "Bash",
            toolInput: #"{"command":"curl https://example.com"}"#,
            conversation: conversation
        )
        fixture.context.insert(approvalRecord)
        try fixture.context.save()

        let sessionFileURL = try writeClaudeSessionFile(
            sessionId: sessionId,
            cwd: fixture.project.path,
            toolUseId: toolUseId,
            decision: "allow"
        )
        defer { try? FileManager.default.removeItem(at: sessionFileURL) }

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
    }

    func testHydrateRecognizesSnakeCaseHookAttachmentToolUseId() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let sessionId = "session-restored"
        let toolUseId = "tool-restored"
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: sessionId,
            toolId: toolUseId,
            toolName: "Bash",
            toolInput: #"{"command":"date"}"#,
            conversation: conversation
        )
        fixture.context.insert(approvalRecord)
        try fixture.context.save()

        let sessionFileURL = try writeClaudeSessionFile(
            sessionId: sessionId,
            cwd: fixture.project.path,
            toolUseId: toolUseId,
            decision: "deny",
            usesSnakeCaseToolUseId: true
        )
        defer { try? FileManager.default.removeItem(at: sessionFileURL) }

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
    }

    func testHydrateMarksAskUserQuestionHookErrorSuperseded() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let sessionId = "session-restored"
        let toolUseId = "prompt-restored"
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: sessionId,
            toolId: toolUseId,
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[{"question":"Pick one","options":[{"label":"A"}]}]}"#,
            conversation: conversation
        )
        fixture.context.insert(approvalRecord)
        try fixture.context.save()

        let sessionFileURL = try writeClaudeSessionFile(
            sessionId: sessionId,
            cwd: fixture.project.path,
            toolUseId: toolUseId,
            hookError: true
        )
        defer { try? FileManager.default.removeItem(at: sessionFileURL) }

        fixture.viewModel.hydratePendingToolApprovalIfNeeded()

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
    }

    func testAnswerPromptSendsNormalMessageWhenRestoredAskUserQuestionHookAlreadyFailed() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let sessionId = "session-restored"
        let toolUseId = "prompt-restored"
        let promptInput = #"{"questions":[{"question":"Pick one","options":[{"label":"A","description":"First"}]}]}"#
        let records = try insertRestoredAskUserQuestion(
            fixture: fixture,
            sessionId: sessionId,
            toolUseId: toolUseId,
            promptInput: promptInput
        )

        let sessionFileURL = try writeClaudeSessionFile(
            sessionId: sessionId,
            cwd: fixture.project.path,
            toolUseId: toolUseId,
            hookError: true
        )
        defer { try? FileManager.default.removeItem(at: sessionFileURL) }

        let summary = try await fixture.viewModel.answerPrompt(
            promptId: toolUseId,
            answers: [(question: "Pick one", answer: "A")]
        )

        XCTAssertEqual(summary, "Q: Pick one\nA: A")
        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(records.approval.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertEqual(records.prompt.content, "Q: Pick one\nA: A")
        let approvalCalls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(approvalCalls.isEmpty)
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["For the question 'Pick one': A"])
    }

    private func insertRestoredAskUserQuestion(
        fixture: ConversationViewModelTestFixture,
        sessionId: String,
        toolUseId: String,
        promptInput: String
    ) throws -> (prompt: ConversationEventRecord, approval: ConversationEventRecord) {
        let conversation = try fixture.dbConversation()
        let promptRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_call",
            toolId: toolUseId,
            toolName: "AskUserQuestion",
            toolInput: promptInput,
            conversation: conversation
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: sessionId,
            toolId: toolUseId,
            toolName: "AskUserQuestion",
            toolInput: promptInput,
            conversation: conversation
        )
        fixture.context.insert(promptRecord)
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.grouper.append(event: promptRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: ToolApprovalRequest(
                sessionId: sessionId,
                toolUseId: toolUseId,
                toolName: "AskUserQuestion",
                toolInput: promptInput
            ),
            status: .pending
        )
        return (promptRecord, approvalRecord)
    }

    private func writeClaudeSessionFile(
        sessionId: String,
        cwd: String,
        toolUseId: String,
        decision: String = "allow",
        usesSnakeCaseToolUseId: Bool = false,
        hookError: Bool = false
    ) throws -> URL {
        let sessionFilePath = try XCTUnwrap(ClaudeAdapter().sessionFilePath(sessionId: sessionId, cwd: cwd))
        let sessionFileURL = URL(fileURLWithPath: sessionFilePath)
        try FileManager.default.createDirectory(
            at: sessionFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let toolUseIdKey = usesSnakeCaseToolUseId ? "tool_use_id" : "toolUseID"
        var events: [[String: Any]] = []
        if !hookError {
            events.append([
                "type": "attachment",
                "attachment": [
                    "type": "hook_deferred_tool",
                    toolUseIdKey: toolUseId,
                    "toolName": "Bash",
                    "toolInput": ["command": "curl https://example.com"]
                ]
            ])
        }

        if hookError {
            events.append([
                "type": "attachment",
                "attachment": [
                    "type": "hook_non_blocking_error",
                    toolUseIdKey: toolUseId,
                    "stderr": "The socket connection was closed unexpectedly"
                ]
            ])
        } else {
            events.append([
                "type": "attachment",
                "attachment": [
                    "type": "hook_success",
                    toolUseIdKey: toolUseId,
                    "stdout": #"{"hookSpecificOutput":{"permissionDecision":"\#(decision)"}}"#
                ]
            ])
        }

        let contents = try events
            .map { try JSONSerialization.data(withJSONObject: $0, options: [.sortedKeys]) }
            .map { try XCTUnwrap(String(data: $0, encoding: .utf8)) }
            .joined(separator: "\n")
        try contents.write(to: sessionFileURL, atomically: true, encoding: .utf8)
        return sessionFileURL
    }
}
