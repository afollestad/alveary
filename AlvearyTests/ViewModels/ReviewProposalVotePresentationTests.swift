import Foundation
import Testing

@testable import Alveary

@MainActor
struct ReviewProposalVotePresentationTests {
    @Test
    func `votes keep abstaining and failed reviewers in the configured denominator`() {
        let presentation = PullRequestReviewVotePresentation(evidence: evidence)

        #expect(presentation.summary == "2/5 agreed")
        #expect(presentation.disclosureLabel(isExpanded: false) == "2 of 5 reviewers agreed. Show vote details")
        let expectedStatuses = ["Agree · P2", "Agree · P2", "Disagree", "Abstain", "Failed / no valid vote"]
        #expect(presentation.reviewers.map(\.status) == expectedStatuses)
        #expect(presentation.reviewers[4].requestedModel == "Requested model: codex · model-4")
    }

    @Test(arguments: [true, false])
    func `embedded carried reviewers win over the current proposal team`(hasEmbeddedReviewers: Bool) {
        let stored = PullRequestReviewProposalRecord.CommentEvidence(
            findingID: evidence.findingID, sourceCandidateIDs: evidence.sourceCandidateIDs,
            priority: evidence.priority, votes: evidence.votes, reviewers: hasEmbeddedReviewers ? reviewers : nil
        )
        let current = [PullRequestReviewProposalRecord.Reviewer(id: "current", providerID: "claude", modelOptionID: "current-model")]
        let presentation = PullRequestReviewVotePresentation(evidence: stored, reviewers: current)

        #expect(presentation.denominator == (hasEmbeddedReviewers ? 5 : 1))
        #expect(presentation.reviewers.first?.requestedModel == (
            hasEmbeddedReviewers ? "Requested model: codex · model-0" : "Requested model: claude · current-model"
        ))
    }

    @Test
    func `both pane paths keep evidence aligned when a manual comment is removed`() async throws {
        let comment = PullRequestReviewProposalRecord.Comment(
            id: "collective-comment", path: "File0.swift", line: 1, side: "RIGHT", body: "**[P2]** Guard this.", evidence: evidence
        )
        let fixture = try ReviewProposalFixture(comments: [
            ReviewProposalFixture.stagedComment(path: "File0.swift", line: 1, body: "Manual comment."), comment
        ])
        fixture.service.detailResult = .success(makePullRequestDetail(id: ReviewProposalFixture.identifier))
        fixture.service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        fixture.coordinator.ensurePreview(proposalID: ReviewProposalFixture.proposalID)
        try await fixture.waitForPreview()
        let before = try #require(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID))
        #expect(before.voteEvidenceByProposedIndex[0] == nil)
        #expect(before.voteEvidenceByProposedIndex[1] == PullRequestReviewVotePresentation(evidence: evidence))

        #expect(fixture.coordinator.removeStagedComment(proposalID: ReviewProposalFixture.proposalID, at: 0))

        let after = try #require(fixture.coordinator.presentation(forProposalID: ReviewProposalFixture.proposalID))
        let threads = PullRequestReviewProposalCoordinator.stagedThreads(
            after.comments, viewerLogin: "viewer", viewerAvatarURL: nil, createdAt: after.createdAt
        )
        let index = try #require(threads.first?.comments.first?.proposedIndex)
        let overviewEvidence = try #require(after.voteEvidenceByProposedIndex[index])
        guard case .loaded(let preview)? = fixture.coordinator.preview(forProposalID: ReviewProposalFixture.proposalID) else {
            Issue.record("Expected a loaded proposal preview")
            return
        }
        let diffComment = try #require(preview.annotations.threads.values.flatMap(\.comments).first)
        #expect(diffComment.proposedIndex == 0)
        #expect(diffComment.voteEvidence == overviewEvidence)
        #expect(after.comments == [comment])
    }

    private var reviewers: [PullRequestReviewProposalRecord.Reviewer] {
        (0..<5).map { index in
            .init(id: index == 0 ? "lead" : "peer-\(index)", providerID: "codex", modelOptionID: "model-\(index)")
        }
    }

    private var evidence: PullRequestReviewProposalRecord.CommentEvidence {
        .init(
            findingID: "finding", sourceCandidateIDs: ["candidate"], priority: 2,
            votes: [
                .init(voterID: "lead", findingID: "finding", decision: .agree, priority: 2, rationale: "Confirmed."),
                .init(voterID: "peer-1", findingID: "finding", decision: .agree, priority: 2, rationale: "Confirmed."),
                .init(voterID: "peer-2", findingID: "finding", decision: .disagree, priority: nil, rationale: "The caller guards this."),
                .init(voterID: "peer-3", findingID: "finding", decision: .abstain, priority: nil, rationale: "The caller is missing.")
            ],
            reviewers: reviewers
        )
    }
}
