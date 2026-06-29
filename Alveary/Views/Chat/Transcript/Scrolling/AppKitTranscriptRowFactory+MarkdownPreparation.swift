import AppKit

extension AppKitTranscriptRowFactory {
    func markdownPreparationRequests(
        for items: [ChatItem],
        configuration: Configuration
    ) -> [AppKitTranscriptMarkdownPrepRequest] {
        items.flatMap { markdownPreparationRequests(for: $0, configuration: configuration) }
    }

    private func markdownPreparationRequests(
        for item: ChatItem,
        configuration: Configuration
    ) -> [AppKitTranscriptMarkdownPrepRequest] {
        switch item {
        case .userMessage(let id, let text):
            let fileAttachments = fileAttachments(for: id, role: .user, configuration: configuration)
            return [markdownPreparationRequest(
                id: id,
                role: .user,
                markdown: displayMarkdown(text, fileAttachments: fileAttachments)
            )]
        case .assistantMessage(let id, let text):
            return [markdownPreparationRequest(id: id, role: .assistant, markdown: text)]
        case .toolApproval(let id, let approval, _):
            return approvalMarkdownPreparationRequests(id: id, approvals: [approval], configuration: configuration)
        case .toolApprovalBatch(let id, let approvals, _):
            return approvalMarkdownPreparationRequests(id: id, approvals: approvals, configuration: configuration)
        case .standaloneTool(let id, let tool):
            return exitPlanModeFollowUpMarkdownPreparationRequest(id: id, tool: tool)
        case .toolGroup,
             .subAgentBlock,
             .taskListBlock,
             .promptBlock,
             .transcriptNote,
             .error:
            return []
        }
    }

    private func markdownPreparationRequest(
        id: String,
        role: AppKitTranscriptTextBubbleRowView.Role,
        markdown: String
    ) -> AppKitTranscriptMarkdownPrepRequest {
        AppKitTranscriptMarkdownPrepRequest(
            rowID: id,
            markdown: markdown,
            inlineCodeStyle: role == .user ? .userBubble : .assistantBubble,
            composerChipMode: role == .user ? .composer : .none
        )
    }

    private func approvalMarkdownPreparationRequests(
        id: String,
        approvals: [ToolApprovalRequest],
        configuration: Configuration
    ) -> [AppKitTranscriptMarkdownPrepRequest] {
        guard let fallbackApproval = approvals.last else {
            return []
        }
        let approval = actionableApproval(in: approvals, pendingToolApproval: configuration.pendingToolApproval) ?? fallbackApproval
        guard let planMarkdown = approvalPlanMarkdown(for: approvals, actionableApproval: approval) else {
            return []
        }
        return [markdownPreparationRequest(id: "\(id)-plan", role: .assistant, markdown: planMarkdown)]
    }

    private func exitPlanModeFollowUpMarkdownPreparationRequest(
        id: String,
        tool: ToolEntry
    ) -> [AppKitTranscriptMarkdownPrepRequest] {
        guard tool.previewOverride?.origin == .exitPlanModeFollowUp,
              let snapshot = MinimalToolContent.snapshot(for: tool),
              snapshot.language == "markdown",
              let content = snapshot.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return [markdownPreparationRequest(id: "\(id)-plan-preview", role: .assistant, markdown: content)]
    }
}
