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

    func testDuplicateToolApprovalEventDoesNotPersistDuplicateRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )

        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))
        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let approvalRecords = records.filter { $0.type == "tool_approval" }
        XCTAssertEqual(approvalRecords.count, 1)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, approval)
    }

    func testNewDeferredApprovalSupersedesOlderUnresolvedApprovalRow() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let oldApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"ls old.txt\"}"
        )
        let oldApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: oldApproval.sessionId,
            toolId: oldApproval.toolUseId,
            toolName: oldApproval.toolName,
            toolInput: oldApproval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(oldApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: oldApproval, status: .pending)

        let newApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-2",
            toolName: "Write",
            toolInput: "{\"file_path\":\"test-permission-2.txt\"}"
        )

        fixture.viewModel.handleEvent(.toolApprovalRequested(newApproval))

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, newApproval)
        XCTAssertEqual(oldApprovalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        let approvalItems = fixture.viewModel.state.grouper.items.compactMap { item -> (String, ToolApprovalStatus?)? in
            guard case .toolApproval(_, let approval, let status) = item else {
                return nil
            }
            return (approval.toolUseId, status)
        }
        XCTAssertEqual(approvalItems.count, 2)
        XCTAssertEqual(approvalItems.first(where: { $0.0 == "tool-1" })?.1, .superseded)
        XCTAssertNil(approvalItems.first(where: { $0.0 == "tool-2" })?.1)
    }

    func testLiveParallelApprovalKeepsOlderUnresolvedApprovalRowAvailableForBatchApproval() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let oldApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"date\"}"
        )
        let oldApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: oldApproval.sessionId,
            toolId: oldApproval.toolUseId,
            toolName: oldApproval.toolName,
            toolInput: oldApproval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(oldApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: oldApproval, status: .pending)

        let newApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-2",
            toolName: "Bash",
            toolInput: "{\"command\":\"pwd\"}"
        )

        fixture.viewModel.handleEvent(.toolApprovalRequested(newApproval))

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, newApproval)
        XCTAssertNil(oldApprovalRecord.toolApprovalStatus)
    }

    func testToolApprovalFailureSupersedesMatchingPendingApproval() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"pwd\"}"
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(approvalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        fixture.viewModel.handleEvent(.toolApprovalFailed(ToolApprovalFailure(
            sessionId: approval.sessionId,
            toolUseId: approval.toolUseId,
            toolName: approval.toolName,
            message: "Claude hook failed (PreToolUse:Bash): socket closed"
        )))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Claude hook failed (PreToolUse:Bash): socket closed")
        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())
        let errorRecord = try XCTUnwrap(records.first { $0.type == "error" })
        XCTAssertEqual(errorRecord.type, "error")
        XCTAssertEqual(errorRecord.toolId, approval.toolUseId)
        XCTAssertEqual(errorRecord.toolName, approval.toolName)
    }

    func testToolApprovalFailureSupersedesMatchingStoredApprovalEvenWhenPendingDiffers() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let failedApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"pwd\"}"
        )
        let currentApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-2",
            toolName: "Bash",
            toolInput: "{\"command\":\"date\"}"
        )
        let failedApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: failedApproval.sessionId,
            toolId: failedApproval.toolUseId,
            toolName: failedApproval.toolName,
            toolInput: failedApproval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(failedApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: currentApproval, status: .pending)

        fixture.viewModel.handleEvent(.toolApprovalFailed(ToolApprovalFailure(
            sessionId: nil,
            toolUseId: failedApproval.toolUseId,
            toolName: failedApproval.toolName,
            message: "Claude hook failed (PreToolUse:Bash): socket closed"
        )))

        XCTAssertEqual(failedApprovalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, currentApproval)
        XCTAssertEqual(fixture.viewModel.lastTurnError, "Claude hook failed (PreToolUse:Bash): socket closed")
    }

    func testNewDeferredApprovalPersistsPreviousResolvedChoiceBeforeReplacingPendingApproval() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let oldApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"ls old.txt\"}"
        )
        let oldApprovalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: oldApproval.sessionId,
            toolId: oldApproval.toolUseId,
            toolName: oldApproval.toolName,
            toolInput: oldApproval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(oldApprovalRecord)
        try fixture.context.save()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: oldApproval, status: .approving)

        let newApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-2",
            toolName: "Write",
            toolInput: "{\"file_path\":\"test-permission-2.txt\"}"
        )

        fixture.viewModel.handleEvent(.toolApprovalRequested(newApproval))

        XCTAssertEqual(fixture.viewModel.state.pendingToolApproval?.request, newApproval)
        XCTAssertEqual(oldApprovalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
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
        fixture.viewModel.state.lastObservedEventIndex = 7
        fixture.viewModel.state.lastPersistedEventIndex = 5
        fixture.viewModel.state.activeBufferGeneration = UUID()
        fixture.viewModel.state.activeRuntimeActivityTurnId = "turn-1"

        try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(fixture.viewModel.state.lastObservedEventIndex, 0)
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 0)
        XCTAssertNil(fixture.viewModel.state.activeBufferGeneration)
        XCTAssertNil(fixture.viewModel.state.activeRuntimeActivityTurnId)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        XCTAssertEqual(calls.first?.approval, approval)
    }

    func testApproveToolUseDuringActiveTurnRecordsLiveHookDecisionWithoutResubscribing() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: true)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)
        await fixture.agentsManager.enableSubscription()

        try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertTrue(fixture.viewModel.state.turnState.isActive)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        let subscribeCalls = await fixture.agentsManager.subscribeCalls()
        XCTAssertEqual(subscribeCalls, 0)
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

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
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

    func testResolvedApprovalPersistsApprovedStatusOnApprovalRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(approvalRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .approving)

        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: false,
                stopReason: "end_turn",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
    }

    func testResolvedApprovalPersistsDeniedStatusOnApprovalRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"swift test\"}"
        )
        let approvalRecord = ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            content: approval.sessionId,
            toolId: approval.toolUseId,
            toolName: approval.toolName,
            toolInput: approval.toolInput,
            conversation: conversation
        )
        fixture.context.insert(approvalRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .denying)

        fixture.viewModel.handleEvent(
            .tokens(
                input: 1,
                output: 1,
                cacheRead: 0,
                isError: false,
                stopReason: "end_turn",
                durationMs: 10,
                costUsd: 0,
                permissionDenials: []
            )
        )

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
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

}
