import Foundation

/// Shared vote labels keep the pane and transcript honest about missing reviewers and the fixed denominator.
struct PullRequestReviewVotePresentation: Hashable, Sendable {
    struct Reviewer: Hashable, Sendable, Identifiable {
        let id: String
        let title: String
        let requestedModel: String
        let status: String
        let rationale: String

        var accessibilityLabel: String { "\(title), \(status). \(requestedModel)" }
    }

    let findingID: String
    let agreeing: Int
    let denominator: Int
    let reviewers: [Reviewer]

    var summary: String { "\(agreeing)/\(denominator) agreed" }
    var accessibilityLabel: String { "Collective review evidence for finding \(findingID)" }

    init(
        evidence: PullRequestReviewProposalRecord.CommentEvidence,
        reviewers: [PullRequestReviewProposalRecord.Reviewer] = []
    ) {
        self.init(findingID: evidence.findingID, votes: evidence.votes, reviewers: evidence.reviewers ?? reviewers)
    }

    init(findingID: String, votes: [ReviewTeamVote], reviewers: [PullRequestReviewProposalRecord.Reviewer]) {
        self.findingID = findingID
        let votesByReviewer = Dictionary(votes.map { ($0.voterID, $0) }, uniquingKeysWith: { _, latest in latest })
        let reviewerIDs = Set(reviewers.map(\.id))
        agreeing = reviewers.isEmpty
            ? votesByReviewer.values.filter { $0.decision == .agree }.count
            : reviewers.filter { votesByReviewer[$0.id]?.decision == .agree }.count
        denominator = reviewers.isEmpty ? votesByReviewer.count : reviewers.count
        self.reviewers = reviewers.enumerated().map { index, reviewer in
            Self.reviewer(
                id: reviewer.id,
                title: reviewer.id == "lead" ? "Lead reviewer" : "Reviewer \(index + 1)",
                model: "Requested model: \(reviewer.providerID) · \(reviewer.modelOptionID)",
                vote: votesByReviewer[reviewer.id]
            )
        } + votes.filter { !reviewerIDs.contains($0.voterID) }.map { vote in
            Self.reviewer(id: vote.voterID, title: "Reviewer \(vote.voterID)", model: "Requested model unavailable", vote: vote)
        }
    }

    func disclosureLabel(isExpanded: Bool) -> String {
        "\(agreeing) of \(denominator) reviewers agreed. \(isExpanded ? "Hide" : "Show") vote details"
    }

    private static func reviewer(id: String, title: String, model: String, vote: ReviewTeamVote?) -> Reviewer {
        let decision = switch vote?.decision {
        case .agree: "Agree"
        case .disagree: "Disagree"
        case .abstain: "Abstain"
        case nil: "Failed / no valid vote"
        }
        return Reviewer(
            id: id,
            title: title,
            requestedModel: model,
            status: vote?.priority.map { "\(decision) · P\($0)" } ?? decision,
            rationale: vote?.rationale.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        )
    }
}
