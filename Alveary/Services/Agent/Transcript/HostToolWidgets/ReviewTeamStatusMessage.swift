import Foundation

/// One reviewer's status update, rendered as a bot message beneath its collective review card.
///
/// A pure projection of `ReviewTeamRun.history`, never a persisted event: a stored message would
/// reach `Conversation.restoreContext`, need deduplicating when `recover()` replays a run, and need
/// a fork policy. History is append-only, so messages never reorder or vanish.
struct ReviewTeamStatusMessage: Equatable, Identifiable {
    enum Author: Equatable {
        case reviewer(ReviewWorkerConfiguration, role: String)
        case team
    }

    enum State: Equatable {
        case working, done, failed
    }

    let id: String
    let author: Author
    let state: State
    let text: String

    /// Nil for team messages, which open the run's overview.
    var reviewerID: String? {
        guard case .reviewer(let member, _) = author else { return nil }
        return member.id
    }

    /// The card drops its reviewer rows only when these messages carry them; a legacy or partially
    /// recorded run has no complete history to project, so it keeps the rows instead.
    static func carriesReviewerStatus(_ run: ReviewTeamRun) -> Bool {
        run.history != nil && run.historyIsPartial != true
    }

    static func messages(for run: ReviewTeamRun) -> [ReviewTeamStatusMessage] {
        guard carriesReviewerStatus(run), let history = run.history else { return [] }
        var messages = history.enumerated().compactMap { index, attempt -> ReviewTeamStatusMessage? in
            guard let memberIndex = run.team.firstIndex(where: { $0.id == attempt.reviewerID }) else { return nil }
            let member = run.team[memberIndex]
            let later = history[(index + 1)...].filter { $0.reviewerID == attempt.reviewerID && $0.phase == attempt.phase }
            let (state, text) = status(of: attempt, in: run, isLatest: later.isEmpty, isRetried: later.contains {
                $0.generation == attempt.generation
            })
            return ReviewTeamStatusMessage(
                id: "collective-review-message:\(run.id):\(attempt.id)",
                author: .reviewer(member, role: member.id == "lead" ? "Lead" : "Peer \(memberIndex)"),
                state: state,
                text: text
            )
        }
        if let text = teamSummary(run) {
            messages.append(ReviewTeamStatusMessage(
                id: "collective-review-message:\(run.id):consensus", author: .team, state: .done, text: text
            ))
        }
        return messages
    }
}

private extension ReviewTeamStatusMessage {
    static func status(
        of attempt: ReviewTeamAttempt,
        in run: ReviewTeamRun,
        isLatest: Bool,
        isRetried: Bool
    ) -> (State, String) {
        switch attempt.status {
        case .running:
            return (.working, runningText(attempt.phase, in: run))
        case .succeeded:
            return (.done, finishedText(attempt, in: run, isLatest: isLatest))
        case .invalid:
            return isRetried ? (.done, "Returned an invalid response. Retrying.") : (.failed, "Returned an invalid response.")
        case .failed:
            let error = attempt.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !error.isEmpty else { return (.failed, "Failed.") }
            return (.failed, "Failed: \(error.count > 240 ? "\(error.prefix(239))…" : error)")
        case .cancelled:
            return (.done, "Stopped.")
        case .interrupted:
            return (.done, "Interrupted.")
        }
    }

    static func runningText(_ phase: ReviewTeamRun.Phase, in run: ReviewTeamRun) -> String {
        switch phase {
        case .consolidating:
            "Merging \(count(candidateCount(run), "finding")) from \(count(run.inspections.count, "reviewer"))…"
        case .crossChecking:
            run.canonical.map { "Cross-checking \(count($0.findings.count, "finding"))…" } ?? "Cross-checking the findings…"
        default:
            "Inspecting the changes…"
        }
    }

    /// Only the reviewer's newest attempt at a step owns the report on the run, so an older success
    /// cannot claim counts a later attempt replaced.
    static func finishedText(_ attempt: ReviewTeamAttempt, in run: ReviewTeamRun, isLatest: Bool) -> String {
        switch attempt.phase {
        case .consolidating:
            guard isLatest, let canonical = run.canonical else { return "Finished merging findings." }
            return "Merged \(count(candidateCount(run), "finding")) from \(count(run.inspections.count, "reviewer")) "
                + "into \(canonical.findings.count)."
        case .crossChecking:
            guard isLatest, let votes = run.voteReports[attempt.reviewerID]?.votes else { return "Finished cross-checking." }
            let total = run.canonical?.findings.count ?? votes.count
            let tally = [
                (ReviewTeamVote.Decision.agree, "agreed with"),
                (.disagree, "disagreed with"),
                (.abstain, "abstained on")
            ].compactMap { decision, verb in
                let matching = votes.filter { $0.decision == decision }.count
                return matching > 0 ? "\(verb) \(matching)" : nil
            }
            let prefix = "Cross-checked \(count(total, "finding"))"
            return tally.isEmpty ? "\(prefix)." : "\(prefix): \(tally.joined(separator: ", "))."
        default:
            guard isLatest, let findings = run.inspections[attempt.reviewerID]?.findings else { return "Finished inspecting." }
            guard !findings.isEmpty else { return "Finished inspecting: nothing to flag." }
            let priorities = Dictionary(grouping: findings, by: \.priority).sorted { $0.key < $1.key }
                .map { "\($0.value.count) P\($0.key)" }
            return "Finished inspecting: \(count(findings.count, "finding")) (\(priorities.joined(separator: ", ")))."
        }
    }

    static func teamSummary(_ run: ReviewTeamRun) -> String? {
        guard [.staging, .staged, .completed].contains(run.phase) else { return nil }
        if let findings = run.canonical?.findings, !findings.isEmpty {
            return "\(run.accepted.count) of \(count(findings.count, "finding")) reached the "
                + "\(run.requiredVotes)/\(run.team.count) majority."
        }
        let allEmpty = !run.inspections.isEmpty && run.inspections.values.allSatisfy(\.findings.isEmpty)
        return run.canonical == nil && allEmpty ? "No reviewer found anything to flag." : nil
    }

    static func candidateCount(_ run: ReviewTeamRun) -> Int {
        run.inspections.values.reduce(0) { $0 + $1.findings.count }
    }

    static func count(_ value: Int, _ noun: String) -> String {
        "\(value) \(noun)\(value == 1 ? "" : "s")"
    }
}
