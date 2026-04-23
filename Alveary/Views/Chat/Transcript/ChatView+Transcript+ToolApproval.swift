import SwiftUI

extension ChatTranscriptView {
    @ViewBuilder
    func toolApprovalBlock(_ approval: ToolApprovalRequest) -> some View {
        ToolApprovalBlock(
            approval: approval,
            status: approvalStatus(for: approval)
        ) {
            resolveToolApproval(approval, approve: true)
        } onDeny: {
            resolveToolApproval(approval, approve: false)
        }
    }

    func approvalStatus(for approval: ToolApprovalRequest) -> ToolApprovalStatus? {
        guard let pending = viewModel.state.pendingToolApproval,
              pending.request.sessionId == approval.sessionId,
              pending.request.toolUseId == approval.toolUseId else {
            return nil
        }
        return pending.status
    }

    func resolveToolApproval(_ approval: ToolApprovalRequest, approve: Bool) {
        Task {
            do {
                if approve {
                    try await viewModel.approveToolUse(toolUseId: approval.toolUseId)
                } else {
                    try await viewModel.denyToolUse(toolUseId: approval.toolUseId)
                }
            } catch {
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }
}
