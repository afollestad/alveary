import SwiftUI

extension ChatTranscriptView {
    @ViewBuilder
    func toolApprovalBlock(_ approval: ToolApprovalRequest, persistedStatus: ToolApprovalStatus?) -> some View {
        ToolApprovalBlock(
            approval: approval,
            status: approvalStatus(for: approval, persistedStatus: persistedStatus),
            isBlocked: viewModel.hasUnansweredPrompt
        ) {
            resolveToolApproval(approval, approve: true)
        } onApproveForSession: { scope in
            resolveToolApprovalForSession(approval, scope: scope)
        } onDeny: {
            resolveToolApproval(approval, approve: false)
        }
    }

    func approvalStatus(for approval: ToolApprovalRequest, persistedStatus: ToolApprovalStatus?) -> ToolApprovalStatus? {
        if let pending = viewModel.state.pendingToolApproval,
           pending.request.sessionId == approval.sessionId,
           pending.request.toolUseId == approval.toolUseId {
            return pending.status
        }
        return persistedStatus
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

    func resolveToolApprovalForSession(_ approval: ToolApprovalRequest, scope: ToolApprovalSessionScope) {
        Task {
            do {
                try await viewModel.approveToolUseForSession(
                    toolUseId: approval.toolUseId,
                    scope: scope
                )
            } catch {
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }
}
