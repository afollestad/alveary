import AppKit

extension AppKitTranscriptRowFactory {
    func approvalRows(
        id: String,
        approvals: [ToolApprovalRequest],
        persistedStatus: ToolApprovalStatus?,
        configuration: Configuration
    ) -> [AppKitTranscriptLayoutRow] {
        guard let fallbackApproval = approvals.last else {
            return []
        }
        let approval = actionableApproval(in: approvals, pendingToolApproval: configuration.pendingToolApproval) ?? fallbackApproval
        var rows: [AppKitTranscriptLayoutRow] = []

        if let planMarkdown = approvalPlanMarkdown(for: approvals, actionableApproval: approval) {
            rows.append(
                textBubbleRow(
                    id: "\(id)-plan",
                    role: .assistant,
                    markdown: planMarkdown,
                    configuration: configuration
                )
            )
        }

        guard !configuration.suppressesApprovalControls(approval) else {
            return rows
        }

        let approvalRowID = "\(id)-approval"
        let view = cachedView(for: approvalRowID, as: AppKitTranscriptToolApprovalBlockView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: approvalRowID, configuration: configuration)
        view.onApprove = { configuration.onApprove(approval) }
        view.onApproveForSession = { scope in configuration.onApproveForSession(approval, scope) }
        view.onDeny = { configuration.onDeny(approval) }
        view.onSelectApprovalSelection = { selection in
            configuration.onSelectApprovalSelection(approval, selection)
        }
        view.configure(
            .init(
                approval: approval,
                approvals: approvals,
                status: approvalStatus(for: approvals, persistedStatus: persistedStatus, pendingToolApproval: configuration.pendingToolApproval),
                isBlocked: configuration.hasUnansweredPrompt,
                selectedApprovalSelection: configuration.selectedApprovalSelection(approval),
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        rows.append(.init(id: approvalRowID, view: view))
        return rows
    }

    func approvalStatus(
        for approvals: [ToolApprovalRequest],
        persistedStatus: ToolApprovalStatus?,
        pendingToolApproval: PendingToolApproval?
    ) -> ToolApprovalStatus? {
        guard let pendingToolApproval,
              approvals.contains(where: {
                  pendingToolApproval.request.sessionId == $0.sessionId &&
                      pendingToolApproval.request.toolUseId == $0.toolUseId
              })
        else {
            return persistedStatus
        }
        return pendingToolApproval.status
    }

    func actionableApproval(
        in approvals: [ToolApprovalRequest],
        pendingToolApproval: PendingToolApproval?
    ) -> ToolApprovalRequest? {
        guard let pendingToolApproval else {
            return nil
        }
        return approvals.first {
            pendingToolApproval.request.sessionId == $0.sessionId &&
                pendingToolApproval.request.toolUseId == $0.toolUseId
        }
    }

    func approvalPlanMarkdown(
        for approvals: [ToolApprovalRequest],
        actionableApproval: ToolApprovalRequest
    ) -> String? {
        guard approvals.count == 1 else {
            return nil
        }
        return approvals.first?.planMarkdown ?? actionableApproval.planMarkdown
    }

}
