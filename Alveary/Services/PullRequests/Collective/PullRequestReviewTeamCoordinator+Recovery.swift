import Foundation

/// Explicit worker retries retain completed reports and reject stale transcript controls.
extension PullRequestReviewTeamCoordinator {
    func retryFailedReviewers(conversationID: String, runID: String, generation: Int) {
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID),
              let thread = conversation.thread, thread.archivedAt == nil,
              var run = try? conversation.collectiveReviewRun(),
              run.id == runID, run.generation == generation,
              runs[conversationID]?.id == runID, runs[conversationID]?.generation == generation,
              let phase = run.failedReviewersRetryPhase,
              (try? hasUnfinishedReview(for: run.identifier, excludingConversationID: conversationID)) == false else { return }
        run.generation += 1
        run.phase = .preparing
        run.retryPhase = phase
        run.pausedPhase = nil
        run.continuedPhases = run.continuedPhases?.filter { phase == .crossChecking && $0 == .inspecting }
        run.error = nil
        run.finishRunningAttempts(as: .interrupted)
        for member in run.team where run.failures["\(phase.rawValue):\(member.id)"] != nil {
            run.attempts.removeValue(forKey: "\(phase.rawValue):\(member.id)")
            run.failures.removeValue(forKey: "\(phase.rawValue):\(member.id)")
        }
        do {
            try persist(run)
            replaceSettledTask(with: run)
        } catch {
            recordRetryFailure(error, conversationID: conversationID)
        }
    }

    func continueWithMajority(conversationID: String, runID: String, generation: Int) {
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID),
              let thread = conversation.thread, thread.archivedAt == nil,
              var run = try? conversation.collectiveReviewRun(),
              run.id == runID, run.generation == generation,
              runs[conversationID]?.id == runID, runs[conversationID]?.generation == generation,
              run.canContinueWithMajority, let phase = run.pausedPhase,
              (try? hasUnfinishedReview(for: run.identifier, excludingConversationID: conversationID)) == false else { return }
        run.generation += 1
        run.phase = .preparing
        run.pausedPhase = nil
        run.error = nil
        run.continuedPhases = (run.continuedPhases ?? []).filter { $0 != phase } + [phase]
        do {
            try persist(run)
            replaceSettledTask(with: run)
        } catch {
            recordRetryFailure(error, conversationID: conversationID)
        }
    }

    /// Every worker has settled; quorum allows a choice, never implicit acceptance of a partial review.
    func pauseForPartialCompletion(_ run: ReviewTeamRun, phase: ReviewTeamRun.Phase) throws -> Bool {
        guard run.continuedPhases?.contains(phase) != true else { return false }
        let completed = run.completedReviewerIDs(in: phase)
        guard completed.count < run.team.count else { return false }
        guard run.team.filter({ !completed.contains($0.id) }).allSatisfy({ run.failures["\(phase.rawValue):\($0.id)"] != nil }) else {
            throw ReviewTeamError.invalidOutput("The review phase still has unfinished reviewers.")
        }
        try update(run.conversationID, generation: run.generation) {
            $0.phase = .awaitingDecision
            $0.pausedPhase = phase
            $0.error = nil
        }
        return true
    }
}
