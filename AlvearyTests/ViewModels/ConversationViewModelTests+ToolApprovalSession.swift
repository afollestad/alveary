import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testApproveToolUseForSessionRecordsGroupApprovalAndResumesSession() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git add foo.swift\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveToolUseForSession(
            toolUseId: "tool-1",
            scope: .group
        )

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        XCTAssertEqual(
            calls.first?.sessionApproval,
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: fixture.conversation.id,
                sessionId: "session-123",
                matchKind: .bashCommandGroup,
                matchValue: "git add"
            )
        )
    }

    func testApproveToolUseForSessionFallsBackToOneShotStatusWhenSessionApprovalIsNotEffective() async throws {
        let fixture = try ConversationViewModelTestFixture(
            sessionApprovalEffective: false,
            initialAgentIsRunning: false
        )
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git add foo.swift\"}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveToolUseForSession(
            toolUseId: "tool-1",
            scope: .group
        )

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.decision, .allow)
        XCTAssertEqual(
            calls.first?.sessionApproval,
            AgentSessionApprovalGrant(
                providerId: "claude",
                conversationId: fixture.conversation.id,
                sessionId: "session-123",
                matchKind: .bashCommandGroup,
                matchValue: "git add"
            )
        )
    }

    func testToolApprovalSelectionLoadsStoredSessionSelection() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git add foo.swift\"}"
        )
        await fixture.agentsManager.recordToolApprovalSelection(
            .sessionGroup,
            providerId: "claude",
            conversationId: fixture.conversation.id,
            sessionId: approval.sessionId
        )

        let selection = await fixture.viewModel.toolApprovalSelection(for: approval)

        XCTAssertEqual(selection, .sessionGroup)
    }

    func testRecordToolApprovalSelectionStoresSessionSelection() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git add foo.swift\"}"
        )

        fixture.viewModel.recordToolApprovalSelection(.sessionExact, for: approval)

        try await waitUntil("expected tool approval selection to be stored") {
            await fixture.viewModel.toolApprovalSelection(for: approval) == .sessionExact
        }
    }

    func testResolvedApprovalPersistsApprovedForSessionGroupStatusOnApprovalRecord() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git add foo.swift\"}"
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
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: approval,
            status: .approvingForSessionGroup
        )

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
        XCTAssertEqual(
            approvalRecord.toolApprovalStatus,
            ToolApprovalStatus.approvedForSessionGroup.rawValue
        )
    }

    func testFallbackSessionApprovalPersistsOneShotApprovedStatusOnApprovalRecord() async throws {
        let fixture = try ConversationViewModelTestFixture(
            sessionApprovalEffective: false,
            initialAgentIsRunning: false
        )
        let conversation = try fixture.dbConversation()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git add foo.swift\"}"
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
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveToolUseForSession(
            toolUseId: "tool-1",
            scope: .group
        )
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
        XCTAssertEqual(
            approvalRecord.toolApprovalStatus,
            ToolApprovalStatus.approved.rawValue
        )
    }

    func testPendingExitPlanApprovalRespawnsWithPlanPermissionMode() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        try fixture.dbThread().permissionMode = "default"
        try fixture.context.save()
        fixture.viewModel.state.runtimePermissionMode = "default"
        fixture.viewModel.state.lastNonPlanPermissionMode = "default"
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(request: approval, status: .pending)

        try await fixture.viewModel.approveToolUse(toolUseId: "tool-1")

        let calls = await fixture.agentsManager.approvalCalls()
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls.first?.config.permissionMode, "plan")
    }

    func testResolvedExitPlanApprovalRestoresPreviousNonPlanModeWithoutStatusEvent() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        try fixture.dbThread().permissionMode = "plan"
        try fixture.context.save()
        fixture.viewModel.state.runtimePermissionMode = "plan"
        fixture.viewModel.state.lastNonPlanPermissionMode = "acceptEdits"
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "ExitPlanMode",
            toolInput: "{}"
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
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: approval,
            status: .approving
        )

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
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "acceptEdits")
        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
    }
}
