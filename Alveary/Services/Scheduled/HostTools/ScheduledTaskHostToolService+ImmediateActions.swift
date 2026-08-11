import AgentCLIKit
import Foundation

extension ScheduledTaskHostToolService {
    /// Result status for an action that ran without confirmation. `nonisolated` because
    /// transcript parsing reads it off the main actor.
    nonisolated static let appliedStatus = "applied"

    /// Actions the model may apply directly. Each is reversible from the Scheduled
    /// screen and revision-checked before it runs, so a confirmation step would only
    /// add friction; create and edit change a definition's content and delete is
    /// irreversible, so both keep the native confirmation. `nonisolated` because
    /// transcript parsing reads it off the main actor.
    nonisolated static func appliesWithoutConfirmation(_ action: ScheduledTaskProposalAction) -> Bool {
        switch action {
        case .pause, .resume, .runNow:
            true
        case .create, .edit, .delete:
            false
        }
    }

    /// Applies a reversible, revision-checked action without opening a proposal.
    ///
    /// The same resolvers the confirmation path uses still run first, so revision
    /// conflicts, missing definitions, and invalid state transitions are rejected before
    /// anything mutates. The receipt records the outcome so an exact retry replays it
    /// rather than acting twice — which matters most for run-now.
    func applyImmediately(
        _ request: ScheduledTaskProposalRequest,
        source: ScheduledTaskHostToolSource,
        identity: ScheduledTaskHostToolProposalIdentity,
        context: AgentCLIKit.AgentHostToolCallContext
    ) throws -> AgentCLIKit.AgentHostToolResult {
        let resolution = try resolveProposal(
            request,
            sourceThread: source.thread,
            sourceProviderID: context.providerId.rawValue
        )
        let title = resolution.targetTitleSnapshot ?? "the scheduled task"
        let message = try apply(request, identity: identity, title: title)

        let receipt = ScheduledTaskProposalReceipt(
            deduplicationKey: identity.deduplicationKey,
            // No proposal exists for a directly applied action; the receipt is only a
            // retry ledger, and its identity is the deduplication key.
            proposalID: identity.deduplicationKey,
            action: request.action,
            title: resolution.targetTitleSnapshot,
            outcomeStatus: Self.appliedStatus,
            message: message,
            sourceProcessToken: context.processToken.uuidString.lowercased(),
            createdAt: identity.createdAt
        )
        try persist(receipt, on: source.conversation)
        // The durable marker is what lets a plain-text-fallback provider's widget read
        // as applied — its result JSON never reaches the transcript. Recorded after the
        // consuming save like every proposal outcome; the retry path replays the receipt
        // before reaching here, so an exact retry cannot write a second marker.
        ScheduledTaskProposalOutcomeRecorder.record(
            ScheduledTaskProposalOutcomeTarget(
                proposalID: identity.deduplicationKey,
                sourceConversationID: source.conversation.id,
                title: resolution.targetTitleSnapshot
            ),
            outcome: .confirmed,
            definitionID: request.targetDefinitionID,
            in: modelContext
        )
        return appliedResult(receipt: receipt)
    }
}

private extension ScheduledTaskHostToolService {
    func apply(
        _ request: ScheduledTaskProposalRequest,
        identity: ScheduledTaskHostToolProposalIdentity,
        title: String
    ) throws -> String {
        switch request {
        case let .pause(definitionID, expectedRevision):
            try mutationService.pause(
                definitionID: definitionID,
                expectedRevision: expectedRevision,
                at: identity.createdAt
            )
            return "Paused \(title). Future occurrences stop until it is resumed."
        case let .resume(definitionID, expectedRevision):
            try mutationService.resume(
                definitionID: definitionID,
                expectedRevision: expectedRevision,
                at: identity.createdAt
            )
            return "Resumed \(title). Future occurrences continue from now."
        case let .runNow(definitionID, expectedRevision):
            try startRunNow(
                definitionID: definitionID,
                expectedRevision: expectedRevision,
                identity: identity
            )
            return "Started a run of \(title) now. Its normal schedule is unchanged."
        case .create, .edit, .delete:
            throw ScheduledTaskHostToolServiceError.unsupportedTool
        }
    }

    func startRunNow(
        definitionID: String,
        expectedRevision: Int,
        identity: ScheduledTaskHostToolProposalIdentity
    ) throws {
        let runRequest = try mutationService.prepareRunNow(
            definitionID: definitionID,
            expectedRevision: expectedRevision,
            at: identity.createdAt,
            // The deduplication key is this call's durable identity, so a retried run-now
            // resolves to the same occurrence instead of launching a second run.
            idempotencyKey: identity.deduplicationKey
        )
        guard runNowAction(runRequest) else {
            throw ScheduledTaskHostToolServiceError.runNowUnavailable
        }
    }
}
