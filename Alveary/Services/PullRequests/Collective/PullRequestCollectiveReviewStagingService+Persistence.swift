import Foundation
import SwiftData

extension PullRequestCollectiveReviewStagingService {
    func proposalOwners(for identifier: PullRequestIdentifier) throws -> [PullRequestReviewProposalOwner] {
        let conversations = try modelContext.fetch(PullRequestReviewProposalLookup.proposalHoldingConversations)
        var owners: [PullRequestReviewProposalOwner] = []
        for conversation in conversations {
            guard let record = try conversation.pullRequestReviewProposal() else {
                continue
            }
            if record.identifier == identifier {
                owners.append(PullRequestReviewProposalOwner(conversationID: conversation.id, record: record))
            }
        }
        return owners.sorted { $0.record.createdAt > $1.record.createdAt }
    }

    func contentHash(_ record: PullRequestReviewProposalRecord) throws -> String {
        ReviewTeamDigest.hash(try ReviewTeamDigest.encode(record))
    }

    func replayedReceipt(for request: Request) throws -> HandoffReceipt? {
        let eventID = proposalEventID(request.proposalID)
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate { $0.id == eventID }
        )
        guard let event = try modelContext.fetch(descriptor).first else {
            return nil
        }
        guard event.conversationId == request.sourceConversationID,
              event.type == ConversationEventRecord.pullRequestReviewProposalType,
              let content = event.content,
              let data = content.data(using: .utf8),
              let payload = try? JSONDecoder().decode(
                  ReviewProposalTranscriptPayload.self,
                  from: data
              ),
              payload.runID == request.runID,
              payload.proposalID == request.proposalID else {
            throw ReviewTeamError.conflict
        }
        return HandoffReceipt(
            proposalID: payload.proposalID,
            resultHash: payload.resultHash,
            supersededProposalIDs: payload.supersededProposalIDs
        )
    }

    func sameProposal(
        _ lhs: PullRequestCollectiveReviewStagingSnapshot,
        _ rhs: PullRequestCollectiveReviewStagingSnapshot
    ) -> Bool {
        lhs.proposalOwnerConversationID == rhs.proposalOwnerConversationID
            && lhs.proposalID == rhs.proposalID
            && lhs.proposalContentHash == rhs.proposalContentHash
    }

    func flushPendingChanges() throws {
        do {
            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }

    func lateReceiptOrValidate(
        _ request: Request,
        lateEditState: @MainActor () -> PullRequestReviewProposalEditStateToken?
    ) async throws -> HandoffReceipt? {
        let currentDetail = try await service.fetchDetail(request.identifier)
        try validateRevision(request, detail: currentDetail)
        if let replay = try replayedReceipt(for: request) {
            return replay
        }
        try flushPendingChanges()
        let current = try snapshot(for: request.identifier, editState: nil)
        guard sameProposal(current, request.expectedSnapshot),
              PullRequestReviewProposalEditState.isUnchanged(
                  from: request.expectedSnapshot.editState,
                  to: lateEditState()
              ) else {
            throw ReviewTeamError.conflict
        }
        return nil
    }

    func recordSupersededOutcomes(_ owners: [PullRequestReviewProposalOwner]) {
        for owner in owners {
            PullRequestReviewProposalOutcomeRecorder.record(
                proposalID: owner.record.id,
                sourceConversationID: owner.conversationID,
                outcome: .rejected,
                in: modelContext,
                at: now()
            )
        }
    }

    func commit(
        record: PullRequestReviewProposalRecord,
        request: Request,
        receipt: HandoffReceipt,
        supersededOwners: [PullRequestReviewProposalOwner],
        atomicallyMutateRun: @MainActor (ModelContext, HandoffReceipt) throws -> Void
    ) throws {
        guard let source = modelContext.resolveConversation(conversationID: request.sourceConversationID) else {
            throw ReviewTeamError.missingConversation
        }
        if let sourceProposal = try source.pullRequestReviewProposal(),
           !supersededOwners.contains(where: { $0.record.id == sourceProposal.id }) {
            throw ReviewTeamError.conflict
        }
        let rollback = try CollectiveReviewStagingRollback(
            source: source,
            supersededOwners: supersededOwners,
            context: modelContext
        )
        try PullRequestReviewProposalPreparation.commit(
            in: modelContext,
            save: commitSave,
            restoringOnFailure: rollback.restore
        ) {
            for owner in supersededOwners {
                guard let conversation = modelContext.resolveConversation(conversationID: owner.conversationID),
                      try conversation.pullRequestReviewProposal()?.id == owner.record.id else {
                    throw ReviewTeamError.conflict
                }
                conversation.clearPullRequestReviewProposal()
            }
            try source.storePullRequestReviewProposal(record)
            modelContext.insert(try proposalEvent(request: request, record: record, receipt: receipt, conversation: source))
            try atomicallyMutateRun(modelContext, receipt)
        }
    }

    func proposalEvent(
        request: Request,
        record: PullRequestReviewProposalRecord,
        receipt: HandoffReceipt,
        conversation: Conversation
    ) throws -> ConversationEventRecord {
        let payload = ReviewProposalTranscriptPayload(
            payloadVersion: ReviewProposalTranscriptPayload.currentVersion,
            runID: request.runID,
            proposalID: request.proposalID,
            resultHash: receipt.resultHash,
            identifier: request.identifier,
            event: record.event,
            body: record.body,
            commentCount: record.stagedComments.count,
            pendingCommentCount: record.pendingCommentCountSnapshot,
            supersededProposalIDs: receipt.supersededProposalIDs
        )
        return ConversationEventRecord(
            id: proposalEventID(request.proposalID),
            conversationId: conversation.id,
            type: ConversationEventRecord.pullRequestReviewProposalType,
            content: String(bytes: try ReviewTeamDigest.encode(payload), encoding: .utf8),
            toolId: request.proposalID,
            toolName: HostToolTranscriptCatalog.toolName(PullRequestHostToolCatalog.proposeReviewToolName),
            timestamp: now(),
            conversation: conversation
        )
    }

    func proposalEventID(_ proposalID: String) -> String {
        "collective-review-proposal:\(proposalID)"
    }
}

@MainActor
private struct CollectiveReviewStagingRollback {
    struct ProposalState {
        let conversation: Conversation
        let json: String?
    }

    struct EventState {
        let event: ConversationEventRecord
        let content: String?
    }

    let source: Conversation
    let sourceRunJSON: String?
    let sourceEvents: [ConversationEventRecord]
    let proposalStates: [ProposalState]
    let eventStates: [EventState]

    init(
        source: Conversation,
        supersededOwners: [PullRequestReviewProposalOwner],
        context: ModelContext
    ) throws {
        var conversations = [source]
        for owner in supersededOwners where !conversations.contains(where: { $0.id == owner.conversationID }) {
            guard let conversation = context.resolveConversation(conversationID: owner.conversationID) else {
                throw ReviewTeamError.conflict
            }
            conversations.append(conversation)
        }
        self.source = source
        sourceRunJSON = source.pullRequestReviewRunJSON
        sourceEvents = source.events
        proposalStates = conversations.map { ProposalState(conversation: $0, json: $0.pullRequestReviewProposalJSON) }
        eventStates = source.events.map { EventState(event: $0, content: $0.content) }
    }

    func restore() {
        for state in proposalStates {
            state.conversation.pullRequestReviewProposalJSON = state.json
        }
        source.pullRequestReviewRunJSON = sourceRunJSON
        source.events = sourceEvents
        for state in eventStates {
            state.event.content = state.content
        }
    }
}
