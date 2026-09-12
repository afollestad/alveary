import Foundation

struct ReviewTeamRun: Codable, Equatable, Sendable, Identifiable {
    enum Phase: String, Codable, Sendable {
        case preparing, inspecting, consolidating, crossChecking, awaitingDecision, staging, staged, completed, failed, cancelled, interrupted

        var isWorking: Bool {
            [.preparing, .inspecting, .consolidating, .crossChecking, .staging].contains(self)
        }

        var isUnfinished: Bool { isWorking || self == .interrupted || self == .awaitingDecision }

        var title: String {
            switch self {
            case .preparing: "Preparing review"
            case .inspecting: "Reviewing with team"
            case .consolidating: "Consolidating findings"
            case .crossChecking: "Cross-checking findings"
            case .awaitingDecision: "Review needs a decision"
            case .staging: "Preparing proposal"
            case .staged: "Review proposed"
            case .completed: "No findings proposed"
            case .failed: "Review needs attention"
            case .cancelled: "Review cancelled"
            case .interrupted: "Review interrupted"
            }
        }
    }

    let payloadVersion: Int
    let id: String
    let proposalID: String
    let conversationID: String
    let identifier: PullRequestIdentifier
    let url: URL
    let team: [ReviewWorkerConfiguration]
    let criteria: String
    let priorProposal: PullRequestCollectiveReviewStagingSnapshot
    let createdAt: Date
    var generation: Int
    var phase: Phase
    var baseOID: String?
    var headOID: String?
    var inputHash: String?
    var inspections: [String: ReviewInspectionReport]
    var canonical: ReviewCanonicalReport?
    var voteReports: [String: ReviewVoteReport]
    var accepted: [ReviewAcceptedFinding]
    var attempts: [String: Int]
    var failures: [String: String]
    var error: String?
    var resultHash: String?
    var supersededProposalIDs: [String]
    /// Frozen revisions or prior-proposal conflicts cannot be repaired by retrying the same input.
    var requiresNewRun: Bool?
    /// Nil distinguishes historical runs that never captured exact worker inputs and responses.
    var history: [ReviewTeamAttempt]?
    /// Resumed legacy runs can capture new attempts without claiming their earlier executions were retained.
    var historyIsPartial: Bool?
    /// An explicit failed-worker retry must not rerun completed inspection work after relaunch.
    var retryPhase: Phase?
    /// Partial results cannot advance until the user chooses which completed phase may continue.
    var pausedPhase: Phase?
    var continuedPhases: [Phase]?

    var requiredVotes: Int { ReviewTeamConsensus.requiredVotes(teamSize: team.count) }

    var canRetryFailedReviewers: Bool { failedReviewersRetryPhase != nil }

    var canContinueWithMajority: Bool {
        guard phase == .awaitingDecision, let pausedPhase, failedReviewersRetryPhase == pausedPhase else { return false }
        return completedReviewerIDs(in: pausedPhase).count >= requiredVotes
    }

    func completedReviewerIDs(in phase: Phase) -> Set<String> {
        let reports = phase == .inspecting ? Set(inspections.keys) : Set(voteReports.keys)
        return reports.intersection(team.map(\.id))
    }

    var partialCompletionWarning: String? {
        guard phase == .staged || phase == .completed else { return nil }
        var incomplete: [String] = []
        if inspections.count < team.count { incomplete.append("\(inspections.count)/\(team.count) inspections completed") }
        if canonical?.findings.isEmpty == false, voteReports.count < team.count {
            incomplete.append("\(voteReports.count)/\(team.count) cross-checks completed")
        }
        guard !incomplete.isEmpty else { return nil }
        let outcome = phase == .staged ? "The proposal uses a fixed majority, not unanimous agreement."
            : "The available majority produced no proposal."
        return "Partial team review: \(incomplete.joined(separator: "; ")). \(outcome)"
    }

    /// Recorded reports and failures are written only after execution returns, so this excludes live reviewers.
    var failedReviewersRetryPhase: Phase? {
        guard resultHash == nil, requiresNewRun != true,
              [.inspecting, .crossChecking, .awaitingDecision, .failed, .interrupted].contains(phase) else { return nil }
        let target: Phase = phase == .awaitingDecision ? pausedPhase ?? .preparing : canonical == nil ? .inspecting : .crossChecking
        guard target == .inspecting || target == .crossChecking,
              phase == target || [.awaitingDecision, .failed, .interrupted].contains(phase) else { return nil }
        if target == .crossChecking {
            guard inspections.count >= requiredVotes, canonical?.findings.isEmpty == false else { return nil }
        }
        let completed = completedReviewerIDs(in: target)
        let missing = team.filter { !completed.contains($0.id) }
        guard !missing.isEmpty,
              missing.allSatisfy({ failures["\(target.rawValue):\($0.id)"] != nil }) else { return nil }
        return target
    }
}

extension Conversation {
    func collectiveReviewRun() throws -> ReviewTeamRun? {
        guard let pullRequestReviewRunJSON else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let run = try decoder.decode(ReviewTeamRun.self, from: Data(pullRequestReviewRunJSON.utf8))
        guard run.payloadVersion == 1 else {
            throw ReviewTeamError.invalidOutput("This review was created by a newer version of Alveary.")
        }
        guard run.conversationID == id, (2...5).contains(run.team.count),
              Set(run.team.map(\.id)).count == run.team.count,
              run.team.first?.id == "lead", run.generation >= 0 else {
            throw ReviewTeamError.invalidOutput("The saved review run is invalid.")
        }
        return run
    }

    func storeCollectiveReviewRun(_ run: ReviewTeamRun) throws {
        pullRequestReviewRunJSON = try ReviewTeamDigest.jsonString(run)
    }
}

extension Notification.Name {
    static let pullRequestReviewRunsChanged = Notification.Name("pullRequestReviewRunsChanged")
    static let reviewTeamCancelRequested = Notification.Name("reviewTeamCancelRequested")
    static let reviewTeamRetryRequested = Notification.Name("reviewTeamRetryRequested")
    static let reviewTeamRetryFailedRequested = Notification.Name("reviewTeamRetryFailedRequested")
    static let reviewTeamContinueRequested = Notification.Name("reviewTeamContinueRequested")
    static let reviewTeamConversationWillClose = Notification.Name("reviewTeamConversationWillClose")
    static let reviewTeamConversationDidDelete = Notification.Name("reviewTeamConversationDidDelete")
    static let reviewTeamDetailsRequested = Notification.Name("reviewTeamDetailsRequested")
}

extension ConversationEventRecord {
    static let collectiveReviewRunType = "collective_review_run"
}
