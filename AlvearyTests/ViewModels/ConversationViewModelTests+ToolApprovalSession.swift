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

    func testApproveToolUseForSessionNormalizesRTKWrappedBashGroupApproval() async throws {
        let fixture = try ConversationViewModelTestFixture(initialAgentIsRunning: false)
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"rtk git log --oneline -5\"}"
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
                matchValue: "git log"
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

    func testResolvedApprovalUpdatesDuplicateRowsForSameToolUseAndSession() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let originalApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git log --oneline -5\"}"
        )
        let rewrittenApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"rtk git log --oneline -5\"}"
        )
        let originalApprovalRecord = sessionToolApprovalRecord(conversation: conversation, request: originalApproval, timestamp: 1)
        let rewrittenApprovalRecord = sessionToolApprovalRecord(conversation: conversation, request: rewrittenApproval, timestamp: 2)
        fixture.context.insert(originalApprovalRecord)
        fixture.context.insert(rewrittenApprovalRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: rewrittenApproval,
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
            originalApprovalRecord.toolApprovalStatus,
            ToolApprovalStatus.approvedForSessionGroup.rawValue
        )
        XCTAssertEqual(
            rewrittenApprovalRecord.toolApprovalStatus,
            ToolApprovalStatus.approvedForSessionGroup.rawValue
        )
    }

    func testResolvedApprovalPreservesResolvedDuplicateRowsForSameToolUseAndSession() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        let originalApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git log --oneline -5\"}"
        )
        let rewrittenApproval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"rtk git log --oneline -5\"}"
        )
        let supersededApprovalRecord = sessionToolApprovalRecord(conversation: conversation, request: originalApproval, timestamp: 1)
        let rewrittenApprovalRecord = sessionToolApprovalRecord(conversation: conversation, request: rewrittenApproval, timestamp: 2)
        supersededApprovalRecord.toolApprovalStatus = ToolApprovalStatus.superseded.rawValue
        fixture.context.insert(supersededApprovalRecord)
        fixture.context.insert(rewrittenApprovalRecord)
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: rewrittenApproval,
            status: .approvingForSessionGroup
        )

        fixture.viewModel.handleEvent(.tokens(
            input: 1,
            output: 1,
            cacheRead: 0,
            isError: false,
            stopReason: "end_turn",
            durationMs: 10,
            costUsd: 0,
            permissionDenials: []
        ))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertEqual(supersededApprovalRecord.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertEqual(rewrittenApprovalRecord.toolApprovalStatus, ToolApprovalStatus.approvedForSessionGroup.rawValue)
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

    func testPendingExitPlanApprovalRespawnsWithPlanCollaborationMode() async throws {
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
        XCTAssertEqual(calls.first?.config.permissionMode, "default")
        XCTAssertEqual(calls.first?.config.planModeEnabled, true)
    }

    func testResolvedExitPlanApprovalRestoresPreviousNonPlanModeWithoutStatusEvent() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = true
        try fixture.context.save()
        fixture.viewModel.state.runtimePermissionMode = "acceptEdits"
        fixture.viewModel.state.runtimePlanModeEnabled = true
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
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, false)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
    }

    func testResolvingExitPlanApprovalClearsWhenCollaborationModeLeavesPlan() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        try fixture.dbThread().permissionMode = "default"
        try fixture.dbThread().planModeEnabled = true
        try fixture.context.save()
        fixture.viewModel.state.runtimePermissionMode = "default"
        fixture.viewModel.state.runtimePlanModeEnabled = true
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
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: approval,
            status: .approving
        )

        fixture.viewModel.handleEvent(.collaborationModeChanged(false))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertTrue(fixture.viewModel.state.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "default")
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
        XCTAssertEqual(try fixture.dbThread().permissionMode, "default")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, false)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
    }

    func testResolvingExitPlanApprovalClearsWhenExitPlanToolResultSucceeds() throws {
        let fixture = try ConversationViewModelTestFixture()
        let conversation = try fixture.dbConversation()
        try fixture.dbThread().permissionMode = "acceptEdits"
        try fixture.dbThread().planModeEnabled = true
        try fixture.context.save()
        fixture.viewModel.state.runtimePermissionMode = "acceptEdits"
        fixture.viewModel.state.runtimePlanModeEnabled = true
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
        fixture.viewModel.state.turnState.beginTurn()
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: approval,
            status: .approving
        )

        fixture.viewModel.handleEvent(.toolResult(
            id: approval.toolUseId,
            output: "Exited plan mode.",
            isError: false,
            parentToolUseId: nil,
            metadata: nil
        ))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertTrue(fixture.viewModel.state.turnState.isActive)
        XCTAssertEqual(fixture.viewModel.state.runtimePermissionMode, "acceptEdits")
        XCTAssertEqual(fixture.viewModel.state.runtimePlanModeEnabled, false)
        XCTAssertEqual(try fixture.dbThread().permissionMode, "acceptEdits")
        XCTAssertEqual(try fixture.dbThread().planModeEnabled, false)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
    }
}

private func sessionToolApprovalRecord(
    conversation: Conversation,
    request: ToolApprovalRequest,
    timestamp: TimeInterval
) -> ConversationEventRecord {
    ConversationEventRecord(
        conversationId: conversation.id,
        type: "tool_approval",
        content: request.sessionId,
        toolId: request.toolUseId,
        toolName: request.toolName,
        toolInput: request.toolInput,
        timestamp: Date(timeIntervalSince1970: timestamp),
        conversation: conversation
    )
}
