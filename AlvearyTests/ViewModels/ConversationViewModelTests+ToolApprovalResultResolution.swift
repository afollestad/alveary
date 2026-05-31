import XCTest
import SwiftData

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testMatchingToolResultApprovesAndClearsUnresolvedPendingApproval() throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = bashApproval()

        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))
        fixture.viewModel.handleEvent(toolResultEvent(toolUseId: approval.toolUseId))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        let approvalRecord = try XCTUnwrap(toolApprovalRecords(in: fixture).first)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.approved.rawValue)
        XCTAssertEqual(renderedApprovalStatus(in: fixture), .approved)
    }

    func testLateToolApprovalEventAfterMatchingResultIsIgnored() throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = bashApproval()

        fixture.viewModel.handleEvent(toolResultEvent(toolUseId: approval.toolUseId))
        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        XCTAssertTrue(toolApprovalRecords(in: fixture).isEmpty)
    }

    func testMatchingToolResultPreservesPendingDeniedApprovalStatus() throws {
        let fixture = try ConversationViewModelTestFixture()
        let approval = bashApproval()

        fixture.viewModel.handleEvent(.toolApprovalRequested(approval))
        fixture.viewModel.state.pendingToolApproval = PendingToolApproval(
            request: approval,
            status: .denying
        )
        fixture.viewModel.handleEvent(toolResultEvent(toolUseId: approval.toolUseId, isError: true))

        XCTAssertNil(fixture.viewModel.state.pendingToolApproval)
        let approvalRecord = try XCTUnwrap(toolApprovalRecords(in: fixture).first)
        XCTAssertEqual(approvalRecord.toolApprovalStatus, ToolApprovalStatus.denied.rawValue)
        XCTAssertEqual(renderedApprovalStatus(in: fixture), .denied)
    }
}

private func bashApproval() -> ToolApprovalRequest {
    ToolApprovalRequest(
        sessionId: "session-123",
        toolUseId: "tool-1",
        toolName: "Bash",
        toolInput: "{\"command\":\"git status\"}"
    )
}

@MainActor
private func toolApprovalRecords(in fixture: ConversationViewModelTestFixture) -> [ConversationEventRecord] {
    ((try? fixture.context.fetch(FetchDescriptor<ConversationEventRecord>())) ?? [])
        .filter { $0.type == "tool_approval" }
}

private func toolResultEvent(toolUseId: String, isError: Bool = false) -> ConversationEvent {
    .toolResult(
        id: toolUseId,
        output: "On branch main",
        isError: isError,
        parentToolUseId: nil,
        metadata: nil
    )
}

@MainActor
private func renderedApprovalStatus(in fixture: ConversationViewModelTestFixture) -> ToolApprovalStatus? {
    for item in fixture.viewModel.state.grouper.items {
        guard case .toolApproval(_, _, let status) = item else {
            continue
        }
        return status
    }
    return nil
}
