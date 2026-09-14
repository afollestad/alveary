import AppKit

/// Immutable content projection paired with the latest layout and action inputs for installation.
@MainActor
struct AppKitTranscriptPreparedUpdate {
    let presentation: AppKitTranscriptPresentation
    var items: [ChatItem] { presentation.items }
    let transientRows: AppKitTranscriptTransientRows
    let rowConfiguration: AppKitTranscriptRowFactory.Configuration
    let isFollowing: Bool
    let scrollToBottomRequest: Int
    let scrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest?

    var contentSignature: ContentSignature {
        ContentSignature(
            items: items,
            transientRows: transientRows,
            bubbleMaxWidth: rowConfiguration.bubbleMaxWidth,
            typography: rowConfiguration.typography,
            markdownBaseURL: rowConfiguration.markdownBaseURL,
            expandedRowIDs: rowConfiguration.expandedRowIDs,
            pendingToolApproval: rowConfiguration.pendingToolApproval,
            retryableFailedMessageIDs: rowConfiguration.retryableFailedMessageIDs,
            transcriptImageAttachmentsByMessageID: rowConfiguration.transcriptImageAttachmentsByMessageID,
            transcriptFileAttachmentsByMessageID: rowConfiguration.transcriptFileAttachmentsByMessageID,
            hasUnansweredPrompt: rowConfiguration.hasUnansweredPrompt,
            isRestoringToolApproval: rowConfiguration.isRestoringToolApproval,
            actionContextID: rowConfiguration.actionContextID,
            approvalSelections: approvalSelections,
            pullRequestLinkPromptsByMessageID: rowConfiguration.pullRequestLinkPromptsByMessageID,
            pullRequestPromptSelections: pullRequestPromptSelections,
            scheduledProposalStates: scheduledProposalStates,
            conversationScheduledProposal: rowConfiguration.conversationScheduledProposal(),
            scheduledTaskRows: rowConfiguration.scheduledTaskListActions.rows(),
            isResolvingScheduledProposal: rowConfiguration.isResolvingScheduledProposal,
            scheduledProposalErrorMessage: rowConfiguration.scheduledProposalErrorMessage,
            reviewProposalStates: reviewProposalStates,
            conversationReviewProposal: rowConfiguration.conversationReviewProposal()
        )
    }

    /// Review-proposal cards resolve their diff preview, verdict, and in-flight state through
    /// closures too, so the signature carries what those return for the rendered items —
    /// otherwise a loaded preview or a failed submission would never reach the card.
    private var reviewProposalStates: [String: ReviewProposalWidgetState] {
        Dictionary(
            items.compactMap { item -> (String, ReviewProposalWidgetState)? in
                guard let proposalID = item.hostToolWidgetEntry?.reviewProposalID,
                      let state = rowConfiguration.reviewProposalState(proposalID) else {
                    return nil
                }
                return (proposalID, state)
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    /// Host-tool widgets resolve live proposal state through closures, so the signature
    /// has to carry what those closures currently return for the rendered items.
    private var scheduledProposalStates: [String: ScheduledProposalState] {
        Dictionary(
            items.compactMap { item -> (String, ScheduledProposalState)? in
                guard let proposalID = item.hostToolWidgetEntry?.scheduledProposalID else {
                    return nil
                }
                return (
                    proposalID,
                    ScheduledProposalState(
                        presentation: rowConfiguration.scheduledProposalPresentation(proposalID),
                        isInteractive: rowConfiguration.isScheduledProposalInteractive(proposalID)
                    )
                )
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    struct ScheduledProposalState: Equatable {
        let presentation: ScheduledTaskProposalPresentation?
        let isInteractive: Bool
    }

    private var pullRequestPromptSelections: [String: PullRequestLinkPromptSelection] {
        Dictionary(
            rowConfiguration.pullRequestLinkPromptsByMessageID.values.flatMap { prompts in
                prompts.map { ($0.id, rowConfiguration.selectedPullRequestPromptSelection($0.id)) }
            },
            uniquingKeysWith: { _, latest in latest }
        )
    }

    private var approvalSelections: [String: ToolApprovalSelection] {
        Dictionary(items.flatMap { item in
            switch item {
            case .toolApproval(_, let approval, _):
                return [(approval.sessionId, rowConfiguration.selectedApprovalSelection(approval))]
            case .toolApprovalBatch(_, let approvals, _):
                return approvals.map { ($0.sessionId, rowConfiguration.selectedApprovalSelection($0)) }
            case .userMessage,
                 .assistantMessage,
                 .toolGroup,
                 .standaloneTool,
                 .subAgentBlock,
                 .taskListBlock,
                 .hostToolWidget,
                 .promptBlock,
                 .transcriptNote,
                 .error:
                return []
            }
        }, uniquingKeysWith: { _, latest in latest })
    }

    struct ContentSignature: Equatable {
        let items: [ChatItem]
        let transientRows: AppKitTranscriptTransientRows
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography
        let markdownBaseURL: URL?
        let expandedRowIDs: Set<String>
        let pendingToolApproval: PendingToolApproval?
        let retryableFailedMessageIDs: Set<String>
        let transcriptImageAttachmentsByMessageID: [String: [TranscriptImageAttachment]]
        let transcriptFileAttachmentsByMessageID: [String: [LocalFileAttachment]]
        let hasUnansweredPrompt: Bool
        let isRestoringToolApproval: Bool
        let actionContextID: String
        let approvalSelections: [String: ToolApprovalSelection]
        let pullRequestLinkPromptsByMessageID: [String: [PendingPullRequestPrompt]]
        let pullRequestPromptSelections: [String: PullRequestLinkPromptSelection]
        let scheduledProposalStates: [String: ScheduledProposalState]
        let conversationScheduledProposal: ScheduledTaskProposalPresentation?
        let scheduledTaskRows: [ScheduledTaskListRow]
        let isResolvingScheduledProposal: Bool
        let scheduledProposalErrorMessage: String?
        let reviewProposalStates: [String: ReviewProposalWidgetState]
        let conversationReviewProposal: ReviewProposalWidgetState?
    }
}
