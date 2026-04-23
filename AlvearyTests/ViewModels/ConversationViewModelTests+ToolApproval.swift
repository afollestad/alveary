import XCTest
import SwiftData

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testToolApprovalEventPersistsAndSetsPendingApproval() throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )

        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, approval)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .pending)
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        XCTAssertEqual(records.last?.type, "tool_approval")
        XCTAssertEqual(records.last?.toolId, "tool-1")
    }

    func testToolDeferredTokenEndsTurnWithoutError() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()

        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: false,
                stopReason: "tool_deferred",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )

        XCTAssertFalse(fixture.viewModel.state.turnState.isActive)
        XCTAssertNil(fixture.viewModel.lastTurnError)
        XCTAssertFalse(fixture.viewModel.state.showPermissionBanner)
    }

    func testApproveToolUseRecordsDecisionAndResumesSession() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .approving)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        XCTAssertEqual(calls.first?.approval, approval)
    }

    func testDenyToolUseRecordsDecisionAndResumesSession() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.denyToolUse(toolUseId: "tool-1")

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.status, .denying)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .deny)
        XCTAssertEqual(calls.first?.approval, approval)
    }

    func testToolApprovalFailureRestoresPendingStatus() async throws {
        let fixture = try ConversationViewModelTestFixture(
            approvalError: .approvalFailed,
            initialAgentIsRunning: false
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        do {
            try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")
            XCTFail("Expected approval resume to fail")
        } catch {}

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval, PendingToolApproval(request: approval, status: .pending))
        XCTAssertTrue(fixture.viewModel.lastTurnError?.hasPrefix("Tool approval failed:") == true)
    }

    func testAlreadyResolvingToolApprovalIsNotSubmittedAgain() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .approving)

        try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testAlreadyResolvingToolApprovalDoesNotThrowWhileSending() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .approving)
        fixture.viewModel.state.isSendingMessage = true

        try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertTrue(calls.isEmpty)
    }

    func testReconfigureSessionIsRejectedDuringPendingToolApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: false
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        do {
            try await fixture.viewModel.reconfigureSession(config: AgentSpawnConfig(
                providerId: "claude",
                workingDirectory: fixture.project.path,
                permissionMode: "acceptEdits",
                model: nil,
                effort: nil,
                initialPrompt: nil
            ))
            XCTFail("Expected reconfigure to be rejected")
        } catch {}

        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        XCTAssertTrue(reconfigureCalls.isEmpty)
    }

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
}
