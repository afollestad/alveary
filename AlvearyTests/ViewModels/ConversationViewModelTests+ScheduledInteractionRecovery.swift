import AgentCLIKit
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testScopedScheduledSupersessionPreservesManualPendingInteractions() throws {
        let fixture = try ConversationViewModelTestFixture(hasCompletedInitialSetup: true)
        let interactions = makeScopedScheduledInteractions(fixture: fixture)
        for record in interactions.records {
            fixture.context.insert(record)
        }
        try fixture.context.save()
        fixture.viewModel.rebuildChatItemsIfNeeded(
            from: fixture.viewModel.conversationEventRecords(),
            forceFullRebuild: true
        )
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: interactions.manualApproval,
            status: .pending
        )

        XCTAssertTrue(
            fixture.viewModel.supersedeAutomatedScheduledPendingInteractions(
                interactionIDs: [interactions.scheduledApproval.toolUseId]
            )
        )

        XCTAssertEqual(interactions.records[0].content, ChatItemGrouper.handledPromptSummary)
        XCTAssertEqual(interactions.records[1].toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertNil(interactions.records[2].content)
        XCTAssertNil(interactions.records[3].toolApprovalStatus)
        XCTAssertEqual(
            fixture.viewModel.state.pendingToolApproval?.request.toolUseId,
            interactions.manualApproval.toolUseId
        )
        XCTAssertTrue(fixture.viewModel.hasUnansweredPrompt)
    }
}

@MainActor
private func makeScopedScheduledInteractions(
    fixture: ConversationViewModelTestFixture
) -> ScopedScheduledInteractions {
    let scheduledInput = #"{"questions":[{"question":"Scheduled?","header":"Scheduled","options":[],"multiSelect":false}]}"#
    let manualInput = #"{"questions":[{"question":"Manual?","header":"Manual","options":[],"multiSelect":false}]}"#
    let scheduledApproval = ToolApprovalRequest(
        sessionId: "scheduled-session",
        toolUseId: "scheduled-prompt",
        toolName: "AskUserQuestion",
        toolInput: scheduledInput
    )
    let manualApproval = ToolApprovalRequest(
        sessionId: "manual-session",
        toolUseId: "manual-prompt",
        toolName: "AskUserQuestion",
        toolInput: manualInput
    )
    return ScopedScheduledInteractions(
        scheduledApproval: scheduledApproval,
        manualApproval: manualApproval,
        records: [
            overlayAskUserQuestionToolCallRecord(
                conversation: fixture.conversation,
                promptId: scheduledApproval.toolUseId,
                promptInput: scheduledInput,
                timestamp: 1
            ),
            overlayToolApprovalRecord(
                conversation: fixture.conversation,
                approval: scheduledApproval,
                timestamp: 2
            ),
            overlayAskUserQuestionToolCallRecord(
                conversation: fixture.conversation,
                promptId: manualApproval.toolUseId,
                promptInput: manualInput,
                timestamp: 3
            ),
            overlayToolApprovalRecord(
                conversation: fixture.conversation,
                approval: manualApproval,
                timestamp: 4
            )
        ]
    )
}

private struct ScopedScheduledInteractions {
    let scheduledApproval: ToolApprovalRequest
    let manualApproval: ToolApprovalRequest
    let records: [ConversationEventRecord]
}
