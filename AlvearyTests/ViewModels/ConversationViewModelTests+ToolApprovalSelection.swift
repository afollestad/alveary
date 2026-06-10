import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testToolApprovalSelectionReturnsStoredSelectionEvenWhenRequestRecommendsGroup() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = ToolApprovalRequest(
            sessionId: "session-123",
            toolUseId: "tool-1",
            toolName: "Bash",
            toolInput: "{\"command\":\"git status --short\"}"
        )
        await fixture.agentsManager.recordToolApprovalSelection(
            .once,
            providerId: "claude",
            conversationId: fixture.conversation.id,
            sessionId: approval.sessionId
        )

        let selection = await fixture.viewModel.toolApprovalSelection(for: approval)

        XCTAssertEqual(approval.recommendedApprovalSelection, .sessionGroup)
        XCTAssertEqual(selection, .once)
    }
}
