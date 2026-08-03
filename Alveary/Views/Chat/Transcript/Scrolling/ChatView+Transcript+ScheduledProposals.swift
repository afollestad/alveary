import Foundation
import SwiftData

extension ChatTranscriptView {
    /// Wires the transcript's scheduling surfaces: the proposal widget's confirmation
    /// actions and the list tool's live rows.
    ///
    /// Create and edit proposals are reviewed in the shared scheduled-task editor pane
    /// so they get the app's full section set; the remaining actions confirm in place.
    func configureAppKitScheduledProposals(_ configuration: inout AppKitTranscriptRowFactory.Configuration) {
        // Both surfaces resolve their state through closures, so scheduling notifications
        // re-render by bumping this revision rather than by changing any stored input.
        _ = scheduledProposalRevision
        let originThreadID = viewModel.conversation.thread?.persistentModelID
        // The list tool needs no proposal queue, so it is wired before that guard.
        configureAppKitScheduledTaskList(&configuration, originThreadID: originThreadID)
        guard let coordinator = scheduledTaskProposalQueueCoordinator else {
            return
        }
        let conversationID = viewModel.conversation.id
        configuration.isResolvingScheduledProposal = coordinator.isResolving
        configuration.scheduledProposalErrorMessage = coordinator.errorMessage
        configuration.scheduledProposalPresentation = { proposalID in
            coordinator.presentation(forProposalID: proposalID)
        }
        configuration.conversationScheduledProposal = {
            coordinator.presentation(forConversationID: conversationID)
        }
        configuration.isScheduledProposalInteractive = { proposalID in
            // A forked or unrelated conversation renders the same widget read-only.
            coordinator.presentation(forProposalID: proposalID)?.sourceConversationID == conversationID
        }
        configuration.onConfirmScheduledProposal = { proposalID in
            coordinator.confirmActionProposal(proposalID: proposalID)
        }
        configuration.onReviewScheduledProposal = { [scheduledTasksViewModel] proposalID in
            guard let scheduledTasksViewModel,
                  let presentation = coordinator.presentation(forProposalID: proposalID) else {
                return
            }
            scheduledTasksViewModel.requestProposalReview(presentation, originThreadID: originThreadID)
        }
        configuration.onRejectScheduledProposal = { proposalID in
            coordinator.reject(proposalID: proposalID)
        }
        configuration.onOpenScheduledTask = { [scheduledTasksViewModel] definitionID in
            // Opening the task itself keeps the user in the transcript's lane; only an
            // unresolvable task falls back to the Scheduled screen. A card outlives the
            // task it names, so a deleted definition takes that fallback too — otherwise
            // the action reads as broken.
            let didOpenPane = definitionID.flatMap { identifier in
                scheduledTasksViewModel?.requestEditFromTranscript(
                    definitionID: identifier,
                    originThreadID: originThreadID
                )
            } ?? false
            guard !didOpenPane else {
                return
            }
            appState.selectedSidebarItem = .scheduled
        }
    }

    private func configureAppKitScheduledTaskList(
        _ configuration: inout AppKitTranscriptRowFactory.Configuration,
        originThreadID: PersistentIdentifier?
    ) {
        configuration.scheduledTaskListActions = ScheduledTaskListToolActions(
            rows: { [scheduledTasksViewModel] in
                scheduledTasksViewModel?.transcriptScheduledTaskRows ?? []
            },
            onEdit: { [scheduledTasksViewModel] definitionID in
                scheduledTasksViewModel?.requestEditFromTranscript(
                    definitionID: definitionID,
                    originThreadID: originThreadID
                )
            }
        )
    }
}
