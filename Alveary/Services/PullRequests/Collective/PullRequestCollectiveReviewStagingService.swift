import Foundation
import SwiftData

// swiftlint:disable type_name
/// The proposal state a collective review promises to carry forward unchanged.
struct PullRequestCollectiveReviewStagingSnapshot: Codable, Equatable, Sendable {
    let proposalOwnerConversationID: String?
    let proposalID: String?
    let proposalContentHash: String?
    let editState: PullRequestReviewProposalEditStateToken?
}

/// Atomically hands a completed collective review to the existing proposal controls.
@MainActor
final class PullRequestCollectiveReviewStagingService {
    struct Request: Sendable {
        let runID: String
        let proposalID: String
        let sourceConversationID: String
        let identifier: PullRequestIdentifier
        let reviewedBaseOID: String
        let reviewedHeadOID: String
        let event: PullRequestReviewEvent
        let body: String?
        let acceptedFindings: [ReviewAcceptedFinding]
        let team: [ReviewWorkerConfiguration]
        let expectedSnapshot: PullRequestCollectiveReviewStagingSnapshot
    }

    struct HandoffReceipt: Codable, Equatable, Sendable {
        let proposalID: String
        let resultHash: String
        let supersededProposalIDs: [String]
    }

    let modelContext: ModelContext
    let service: any PullRequestsService
    let previewCache: PullRequestReviewProposalPreviewCache?
    let notificationCenter: NotificationCenter
    let now: () -> Date
    let commitSave: (ModelContext) throws -> Void

    init(
        modelContext: ModelContext,
        service: any PullRequestsService,
        previewCache: PullRequestReviewProposalPreviewCache? = nil,
        notificationCenter: NotificationCenter = .default,
        now: @escaping () -> Date = Date.init,
        commitSave: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.service = service
        self.previewCache = previewCache
        self.notificationCenter = notificationCenter
        self.now = now
        self.commitSave = commitSave
    }

    func snapshot(
        for identifier: PullRequestIdentifier,
        editState: PullRequestReviewProposalEditStateToken?
    ) throws -> PullRequestCollectiveReviewStagingSnapshot {
        let owners = try proposalOwners(for: identifier)
        guard owners.count <= 1 else {
            throw ReviewTeamError.conflict
        }
        guard let owner = owners.first else {
            return PullRequestCollectiveReviewStagingSnapshot(
                proposalOwnerConversationID: nil,
                proposalID: nil,
                proposalContentHash: nil,
                editState: nil
            )
        }
        guard editState?.proposalID == nil || editState?.proposalID == owner.record.id else {
            throw ReviewTeamError.conflict
        }
        return PullRequestCollectiveReviewStagingSnapshot(
            proposalOwnerConversationID: owner.conversationID,
            proposalID: owner.record.id,
            proposalContentHash: try contentHash(owner.record),
            editState: editState
        )
    }

    func priorProposal(
        for snapshot: PullRequestCollectiveReviewStagingSnapshot
    ) throws -> PullRequestReviewProposalRecord? {
        guard let ownerID = snapshot.proposalOwnerConversationID,
              let proposalID = snapshot.proposalID,
              let expectedHash = snapshot.proposalContentHash,
              let conversation = modelContext.resolveConversation(conversationID: ownerID),
              let record = try conversation.pullRequestReviewProposal(),
              record.id == proposalID,
              try contentHash(record) == expectedHash else {
            if snapshot.proposalID == nil,
               snapshot.proposalOwnerConversationID == nil,
               snapshot.proposalContentHash == nil {
                return nil
            }
            throw ReviewTeamError.conflict
        }
        return record
    }

    func stage(
        _ request: Request,
        lateEditState: @MainActor () -> PullRequestReviewProposalEditStateToken?,
        atomicallyMutateRun: @MainActor (ModelContext, HandoffReceipt) throws -> Void
    ) async throws -> HandoffReceipt {
        if let receipt = try replayedReceipt(for: request) {
            return receipt
        }

        let prepared = try await prepareHandoff(request)
        await seedPreviewCache(record: prepared.record, detail: prepared.detail, files: prepared.files)

        // Cache I/O suspends. Recheck remote and local state after every await, then mutate without
        // another suspension so no edit can land inside the proposal/run transaction.
        if let replay = try await lateReceiptOrValidate(request, lateEditState: lateEditState) {
            return replay
        }

        let supersededOwners = try proposalOwners(for: request.identifier)
        try commit(
            record: prepared.record,
            request: request,
            receipt: prepared.receipt,
            supersededOwners: supersededOwners,
            atomicallyMutateRun: atomicallyMutateRun
        )
        recordSupersededOutcomes(supersededOwners)
        notificationCenter.post(name: .pullRequestReviewProposalsChanged, object: self)
        return prepared.receipt
    }
}
// swiftlint:enable type_name
