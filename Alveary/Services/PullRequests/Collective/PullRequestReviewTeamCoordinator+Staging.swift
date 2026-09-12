import Foundation

extension PullRequestReviewTeamCoordinator {
    func currentEditState(for identifier: PullRequestIdentifier) -> PullRequestReviewProposalEditStateToken? {
        guard let snapshot = try? staging.snapshot(for: identifier, editState: nil), let proposalID = snapshot.proposalID else { return nil }
        return PullRequestReviewProposalEditState.current(proposalID: proposalID)
    }

    func priorRecord(_ run: ReviewTeamRun) throws -> PullRequestReviewProposalRecord? {
        try staging.priorProposal(for: run.priorProposal)
    }

    func stageResult(_ run: ReviewTeamRun, input: PreparedInput) async throws {
        let prior = try priorRecord(run)
        let isOwn = input.detail.viewerLogin == input.detail.authorLogin
        let carriedBlocker = prior?.stagedComments.first { comment in
            comment.body.range(of: #"^\s*(\*\*)?\[P[01]\]"#, options: .regularExpression) != nil
        }
        let blocker = run.accepted.first { $0.priority <= 1 }
        let requiresChanges = blocker != nil || carriedBlocker != nil || prior?.event == "request_changes"
        let event: PullRequestReviewEvent = isOwn ? .comment : requiresChanges ? .requestChanges : .approve
        var body = prior?.body
        if event == .requestChanges, body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            let finding = blocker?.finding.body ?? carriedBlocker?.body ?? "Please address the staged review findings."
            body = String(finding.components(separatedBy: ". ").first?.prefix(1000) ?? finding.prefix(1000))
        }
        if isOwn, run.accepted.isEmpty, input.detail.pendingCommentCount == 0, prior?.stagedComments.isEmpty != false,
           body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false {
            try await verifyRevision(run)
            let current = try staging.snapshot(for: run.identifier, editState: currentEditState(for: run.identifier))
            guard current.proposalID == run.priorProposal.proposalID,
                  current.proposalOwnerConversationID == run.priorProposal.proposalOwnerConversationID,
                  current.proposalContentHash == run.priorProposal.proposalContentHash,
                  PullRequestReviewProposalEditState.isUnchanged(from: run.priorProposal.editState, to: current.editState) else {
                throw ReviewTeamError.conflict
            }
            try update(run.conversationID, generation: run.generation) { $0.phase = .completed }
            return
        }
        guard let base = run.baseOID, let head = run.headOID else { throw ReviewTeamError.revisionChanged }
        let request = PullRequestCollectiveReviewStagingService.Request(
            runID: run.id, proposalID: run.proposalID, sourceConversationID: run.conversationID,
            identifier: run.identifier, reviewedBaseOID: base, reviewedHeadOID: head, event: event, body: body,
            acceptedFindings: run.accepted, team: run.team, expectedSnapshot: run.priorProposal
        )
        _ = try await staging.stage(request, lateEditState: { [self] in
            currentEditState(for: run.identifier)
        }, atomicallyMutateRun: { [self] context, receipt in
            var current = try requireActive(run.conversationID, generation: run.generation)
            current.phase = .staged
            current.resultHash = receipt.resultHash
            current.supersededProposalIDs = receipt.supersededProposalIDs
            guard let conversation = context.resolveConversation(conversationID: run.conversationID) else {
                throw ReviewTeamError.missingConversation
            }
            try conversation.storeCollectiveReviewRun(current)
            try storeProgressEvent(current, conversation: conversation)
        })
        guard let current = try modelContext.resolveConversation(conversationID: run.conversationID)?.collectiveReviewRun() else {
            throw ReviewTeamError.missingConversation
        }
        didPersist(current)
    }

    func repairSupersededOutcome(_ run: ReviewTeamRun) {
        guard run.phase == .staged, let priorID = run.priorProposal.proposalID,
              run.supersededProposalIDs.contains(priorID),
              let owner = run.priorProposal.proposalOwnerConversationID,
              let conversation = modelContext.resolveConversation(conversationID: owner),
              !conversation.events.contains(where: { $0.type == ConversationEventRecord.hostToolOutcomeType && $0.toolId == priorID }) else {
            return
        }
        PullRequestReviewProposalOutcomeRecorder.record(
            proposalID: priorID, sourceConversationID: owner, outcome: .rejected, in: modelContext
        )
    }
}
