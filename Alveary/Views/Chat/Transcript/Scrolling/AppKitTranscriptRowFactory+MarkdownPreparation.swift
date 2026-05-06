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
            return [markdownPreparationRequest(id: id, role: .user, markdown: text)]
        case .assistantMessage(let id, let text):
            return [markdownPreparationRequest(id: id, role: .assistant, markdown: text)]
        case .toolApproval(let id, let approval, _):
            return approvalMarkdownPreparationRequests(id: id, approvals: [approval], configuration: configuration)
        case .toolApprovalBatch(let id, let approvals, _):
            return approvalMarkdownPreparationRequests(id: id, approvals: approvals, configuration: configuration)
        case .toolGroup,
             .standaloneTool,
             .subAgentBlock,
             .taskListBlock,
             .promptBlock,
             .centeredNote,
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
            inlineCodeStyle: role == .user ? .userBubble : .standard,
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
}
