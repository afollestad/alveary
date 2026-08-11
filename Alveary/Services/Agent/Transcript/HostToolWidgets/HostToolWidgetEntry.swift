import Foundation

/// Durable outcome recorded for a host-tool widget after the user resolves it.
enum HostToolWidgetOutcome: String, Equatable, Sendable {
    case confirmed
    case rejected
}

/// Feature-specific payload rendered by a host-tool widget block.
///
/// Adding a new `alveary_host` feature with custom transcript UI means adding a
/// case here, a parser in `HostToolTranscriptCatalog`, and an AppKit body view.
enum HostToolWidgetContent: Equatable {
    case scheduledTaskProposal(ScheduledTaskProposalWidgetContent)
    case pullRequestLink(PullRequestLinkWidgetContent)
    case pullRequestReviewProposal(PullRequestReviewProposalWidgetContent)
    case pullRequestReviewInstructions(ReviewInstructionsWidgetContent)
    case pullRequestList(PullRequestListWidgetContent)
    case threadAction(ThreadActionWidgetContent)
}

/// What a settled widget's card opens when clicked, and therefore whether it is a control at
/// all. A feature whose card only reports keeps returning `nil`.
enum HostToolWidgetTarget: Equatable {
    case pullRequest(PullRequestIdentifier)
    /// Sole-main-conversation id of the thread; an archived one lands on the Archived screen,
    /// which the app root decides because only it can read the thread's state.
    case thread(String)
}

/// One host MCP tool call rendered as a first-class transcript widget.
struct HostToolWidgetEntry: Identifiable, Equatable {
    let id: String
    let toolName: String
    let content: HostToolWidgetContent
    let isComplete: Bool
    let isInterrupted: Bool
    let isError: Bool
    /// Correlates durable outcome markers with this widget; `nil` when the feature has no outcome.
    let outcomeKey: String?
    let outcome: HostToolWidgetOutcome?
    /// Definition the durable outcome marker recorded, when the feature supplied one.
    let outcomeDefinitionID: String?
    /// Target task name the durable outcome marker recorded, when the feature supplied one.
    let outcomeTitle: String?

    init(
        id: String,
        toolName: String,
        content: HostToolWidgetContent,
        isComplete: Bool,
        isInterrupted: Bool = false,
        isError: Bool = false,
        outcomeKey: String? = nil,
        outcome: HostToolWidgetOutcome? = nil,
        outcomeDefinitionID: String? = nil,
        outcomeTitle: String? = nil
    ) {
        self.id = id
        self.toolName = toolName
        self.content = content
        self.isComplete = isComplete
        self.isInterrupted = isInterrupted
        self.isError = isError
        self.outcomeKey = outcomeKey
        self.outcome = outcome
        self.outcomeDefinitionID = outcomeDefinitionID
        self.outcomeTitle = outcomeTitle
    }

    func withOutcome(
        _ outcome: HostToolWidgetOutcome?,
        definitionID: String? = nil,
        title: String? = nil
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: id,
            toolName: toolName,
            content: content,
            isComplete: isComplete,
            isInterrupted: isInterrupted,
            isError: isError,
            outcomeKey: outcomeKey,
            outcome: outcome ?? self.outcome,
            outcomeDefinitionID: definitionID ?? outcomeDefinitionID,
            outcomeTitle: title ?? outcomeTitle
        )
    }

    /// Queue identifier when this widget represents a scheduling proposal.
    var scheduledProposalID: String? {
        guard case .scheduledTaskProposal(let content) = content else {
            return nil
        }
        return content.proposalID
    }

    /// Scheduled task this widget can open, once the change is in effect. A confirmed
    /// create only learns its definition from the outcome marker.
    var resolvedScheduledTaskID: String? {
        guard case .scheduledTaskProposal(let content) = content else {
            return nil
        }
        return outcomeDefinitionID ?? content.targetDefinitionID
    }

    /// A proposal action that ran without confirmation and is already in effect.
    var isAppliedProposal: Bool {
        guard case .scheduledTaskProposal(let content) = content else {
            return false
        }
        return content.status == .applied
    }

    /// The change this widget describes needs no decision and already took effect: an applied
    /// proposal, or a link or thread mutation whose tool result is itself the outcome.
    var isSettledWithoutDecision: Bool {
        switch content {
        case .scheduledTaskProposal:
            isAppliedProposal
        case .pullRequestLink(let content):
            content.isSettled
        case .pullRequestReviewProposal:
            // Submitting always needs the user, so this card is never settled by its own result.
            false
        case .pullRequestReviewInstructions(let content):
            // A read decides nothing, so a landed one is settled the moment it returns.
            content.status == .loaded || content.status == .loadedWithoutInstructions
        case .pullRequestList(let content):
            // A read decides nothing, so a landed one is settled the moment it returns.
            content.status == .listed || content.status == .listedWithoutRows
        case .threadAction(let content):
            content.isSettled
        }
    }

    /// What this widget's card opens, once its call has landed. A running or refused call has
    /// nothing to open, and neither has one whose result never named its target.
    var openableTarget: HostToolWidgetTarget? {
        switch content {
        case .scheduledTaskProposal:
            // The proposal body carries its own Open action.
            nil
        case .pullRequestLink(let content):
            content.isSettled ? content.identifier.map(HostToolWidgetTarget.pullRequest) : nil
        case .pullRequestReviewProposal(let content):
            // While the decision is open the card carries its own Open PR action, so the bubble is
            // not a button. Resolving drops that whole row — including a rejection, which decides
            // nothing about the pull request — so from then on the card is the only way back to it.
            outcome == nil ? nil : content.identifier.map(HostToolWidgetTarget.pullRequest)
        case .pullRequestReviewInstructions:
            // The disclosure inside the card is its only control; clicking the card itself must
            // toggle that, not navigate away from the review it is starting.
            nil
        case .pullRequestList:
            // Each row opens a different pull request, so the rows are the controls, not the card.
            nil
        case .threadAction(let content):
            content.isSettled ? content.threadID.map(HostToolWidgetTarget.thread) : nil
        }
    }

    /// The pull request this widget can open; `nil` for every other target.
    var openablePullRequest: PullRequestIdentifier? {
        guard case .pullRequest(let identifier) = openableTarget else {
            return nil
        }
        return identifier
    }

    /// A proposal widget still awaiting the user's decision, with no durable outcome yet.
    var isUnresolvedProposal: Bool {
        guard outcome == nil, case .scheduledTaskProposal(let content) = content else {
            return false
        }
        return content.status == .pendingConfirmation
    }

    /// Confirmation identity for a review proposal, and whether it is still awaiting one.
    var reviewProposalID: String? {
        guard case .pullRequestReviewProposal(let content) = content else {
            return nil
        }
        return content.proposalID
    }

    var isUnresolvedReviewProposal: Bool {
        guard outcome == nil, case .pullRequestReviewProposal(let content) = content else {
            return false
        }
        return content.status == .pendingConfirmation
    }

    /// An immediate action's widget between its call and its outcome marker: still
    /// running, or already applied but not yet named by the marker. Keyless markers
    /// pair with these oldest-first; a pending proposal must never adopt one, or an
    /// unrelated confirmation could read as resolved with another task's name.
    var isProposalAwaitingOutcomeMarker: Bool {
        guard outcome == nil, case .scheduledTaskProposal(let content) = content else {
            return false
        }
        return content.status == .running || content.status == .applied
    }

    var terminalizingAsInterruptedIfNeeded: HostToolWidgetEntry {
        guard !isComplete else {
            return self
        }
        return HostToolWidgetEntry(
            id: id,
            toolName: toolName,
            content: content,
            isComplete: true,
            isInterrupted: true,
            isError: isError,
            outcomeKey: outcomeKey,
            outcome: outcome,
            outcomeDefinitionID: outcomeDefinitionID,
            outcomeTitle: outcomeTitle
        )
    }
}

/// A `propose_scheduled_task` call, as recorded durably in the transcript.
///
/// Live confirmation state (draft, conflicts) comes from
/// `ScheduledTaskProposalQueueCoordinator`, never from this snapshot.
struct ScheduledTaskProposalWidgetContent: Equatable {
    enum Status: Equatable {
        /// The call has not returned yet.
        case running
        /// The proposal was opened and is awaiting confirmation.
        case pendingConfirmation
        /// The action was reversible enough to run without confirmation and already did.
        case applied
        /// The host tool rejected the request outright.
        case failed
    }

    let action: ScheduledTaskProposalAction?
    let proposedTitle: String?
    let recurrence: ScheduledTaskRecurrence?
    let timeZoneIdentifier: String?
    /// Definition the action targets, when the request named one.
    let targetDefinitionID: String?
    let proposalID: String?
    let message: String?
    let status: Status

    var isEditorProposal: Bool {
        action == .create || action == .edit
    }

    var scheduleSummary: String? {
        guard let recurrence else {
            return nil
        }
        return ScheduledTaskPresentationFormatting.recurrenceSummary(
            recurrence,
            timeZoneIdentifier: timeZoneIdentifier ?? TimeZone.autoupdatingCurrent.identifier
        )
    }

}

extension ChatItem {
    var hostToolWidgetEntry: HostToolWidgetEntry? {
        guard case .hostToolWidget(_, let entry) = self else {
            return nil
        }
        return entry
    }
}
