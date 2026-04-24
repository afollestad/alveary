import SwiftUI

extension ChatTranscriptView {
    @ViewBuilder
    func toolApprovalBlock(_ approval: ToolApprovalRequest, persistedStatus: ToolApprovalStatus?) -> some View {
        toolApprovalBlock([approval], persistedStatus: persistedStatus)
    }

    @ViewBuilder
    func toolApprovalBlock(_ approvals: [ToolApprovalRequest], persistedStatus: ToolApprovalStatus?) -> some View {
        if let fallbackApproval = approvals.last {
            let approval = actionableApproval(in: approvals) ?? fallbackApproval

            ToolApprovalBlock(
                approval: approval,
                approvals: approvals,
                status: approvalStatus(for: approvals, persistedStatus: persistedStatus),
                isBlocked: viewModel.hasUnansweredPrompt,
                onApprove: {
                    resolveToolApproval(approval, approve: true)
                },
                onApproveForSession: { scope in
                    resolveToolApprovalForSession(approval, scope: scope)
                },
                onDeny: {
                    resolveToolApproval(approval, approve: false)
                },
                loadApprovalSelection: {
                    await viewModel.toolApprovalSelection(for: approval)
                },
                onSelectApprovalSelection: { selection in
                    viewModel.recordToolApprovalSelection(selection, for: approval)
                }
            )
        }
    }

    func approvalStatus(for approval: ToolApprovalRequest, persistedStatus: ToolApprovalStatus?) -> ToolApprovalStatus? {
        approvalStatus(for: [approval], persistedStatus: persistedStatus)
    }

    func approvalStatus(for approvals: [ToolApprovalRequest], persistedStatus: ToolApprovalStatus?) -> ToolApprovalStatus? {
        if let pending = viewModel.state.pendingToolApproval,
           approvals.contains(where: {
               pending.request.sessionId == $0.sessionId &&
                   pending.request.toolUseId == $0.toolUseId
           }) {
            return pending.status
        }
        return persistedStatus
    }

    func actionableApproval(in approvals: [ToolApprovalRequest]) -> ToolApprovalRequest? {
        guard let pending = viewModel.state.pendingToolApproval else {
            return nil
        }

        return approvals.first {
            pending.request.sessionId == $0.sessionId &&
                pending.request.toolUseId == $0.toolUseId
        }
    }
}

private extension ChatTranscriptView {
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
