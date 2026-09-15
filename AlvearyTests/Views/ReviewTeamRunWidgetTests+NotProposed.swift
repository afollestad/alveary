import AppKit
import Testing

@testable import Alveary

@MainActor
extension ReviewTeamRunWidgetTests {
    @Test
    func `not proposed findings render compact paths and reversible markdown previews`() throws {
        let run = notProposedMarkdownRun()
        let canonical = try #require(run.canonical?.findings.first)
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.frame = NSRect(x: 0, y: 0, width: 360, height: 1_500)
        view.configure(.init(entry: HostToolWidgetEntry(
            id: "not-proposed", toolName: "Collective review", content: .collectiveReviewRun(run), isComplete: true, isError: false
        ), bubbleMaxWidth: 360))
        try #require(reviewTeamDescendants(of: NSButton.self, in: view).first { $0.title == "Show 1 not proposed" }).performClick(nil)
        view.layoutSubtreeIfNeeded()

        let finding = try #require(reviewTeamDescendants(of: AppKitReviewTeamNotProposedFindingView.self, in: view).first)
        #expect(finding.findingID == canonical.id)
        let fields = reviewTeamDescendants(of: NSTextField.self, in: finding)
        let location = try #require(fields.first { $0.stringValue == "ReviewTeamCoordinator+CrossChecking.swift:254" })
        #expect(location.toolTip?.contains(canonical.path) == true)
        let accessibleLocation = [location.accessibilityLabel(), location.accessibilityHelp()].compactMap { $0 }.joined(separator: ". ")
        #expect(accessibleLocation.contains(canonical.path))
        #expect(!fields.contains { $0.stringValue.contains(canonical.path) })
        let body = visibleFindingText(in: finding)
        #expect(body.contains("Preserve the completed reports"))
        #expect(!body.contains("**") && !body.contains("`"))
        #expect(reviewTeamDescendants(of: AppKitReviewProposalCompactVoteRowView.self, in: finding).isEmpty)

        let compactHeight = view.intrinsicContentSize.height
        try #require(reviewTeamDescendants(of: NSButton.self, in: finding).first { $0.title == "Show more" }).performClick(nil)
        view.layoutSubtreeIfNeeded()
        #expect(view.intrinsicContentSize.height > compactHeight)
        #expect(visibleFindingText(in: finding).contains("original majority requirement"))
        try #require(reviewTeamDescendants(of: NSButton.self, in: finding).first { $0.title == "Show less" }).performClick(nil)
        view.layoutSubtreeIfNeeded()
        #expect(abs(view.intrinsicContentSize.height - compactHeight) <= 1)
    }

    @Test
    func `compact vote rows disclose rationales individually and retain expansion on updates`() throws {
        let run = notProposedMarkdownRun()
        let finding = try #require(run.canonical?.findings.first)
        let reviewers = run.team.map {
            PullRequestReviewProposalRecord.Reviewer(id: $0.id, harnessID: $0.harnessID, modelOptionID: $0.modelOptionID)
        }
        let votes = run.team.flatMap { run.voteReports[$0.id]?.votes ?? [] }
        let evidence = AppKitReviewProposalVoteEvidenceView()
        let window = NSWindow(contentRect: NSRect(x: -10_000, y: -10_000, width: 500, height: 600),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = evidence
        defer {
            window.makeFirstResponder(nil)
            window.contentView = nil
            window.close()
        }
        var invalidations = 0
        evidence.onHeightInvalidated = { invalidations += 1 }
        evidence.configure(findingID: finding.id, votes: votes, reviewers: reviewers, typography: TranscriptTypography(), compact: true)
        let lead = try expandCompactVotes(in: evidence, reviewerIDs: run.team.map(\.id))
        #expect(window.makeFirstResponder(lead))
        let beforeExpand = invalidations
        #expect(lead.accessibilityPerformPress())
        let expanded = try #require(reviewTeamDescendants(of: AppKitReviewProposalCompactVoteRowView.self, in: evidence).first {
            $0.reviewerID == "lead"
        })
        #expect(expanded.isExpanded)
        #expect(window.firstResponder === expanded)
        #expect(invalidations > beforeExpand)
        #expect(visibleFindingText(in: evidence).contains("removes the previous votes"))
        #expect(!visibleFindingText(in: evidence).contains("preserves the completed reports"))

        var settings = AppSettings()
        settings.chatFontSize = 20
        evidence.configure(
            findingID: finding.id, votes: votes, reviewers: reviewers, typography: TranscriptTypography(settings: settings), compact: true
        )
        let restored = try #require(reviewTeamDescendants(of: AppKitReviewProposalCompactVoteRowView.self, in: evidence).first {
            $0.reviewerID == "lead"
        })
        #expect(restored.isExpanded)
        #expect(window.firstResponder === restored)
        #expect(restored.accessibilityLabel()?.contains("Hide rationale") == true)
        #expect(restored.accessibilityPerformPress())
        let collapsed = try #require(reviewTeamDescendants(of: AppKitReviewProposalCompactVoteRowView.self, in: evidence).first {
            $0.reviewerID == "lead"
        })
        #expect(window.firstResponder === collapsed)
        #expect(!visibleFindingText(in: evidence).contains("removes the previous votes"))
    }

    private func expandCompactVotes(
        in evidence: AppKitReviewProposalVoteEvidenceView, reviewerIDs: [String]
    ) throws -> AppKitReviewProposalCompactVoteRowView {
        #expect(reviewTeamDescendants(of: AppKitReviewProposalCompactVoteRowView.self, in: evidence).isEmpty)
        let aggregate = try #require(reviewTeamDescendants(of: AppKitTranscriptHeaderToggleButton.self, in: evidence).first)
        #expect(aggregate.accessibilityLabel() == "1 of 3 reviewers agreed. Show vote details")
        aggregate.performClick(nil)
        let rows = reviewTeamDescendants(of: AppKitReviewProposalCompactVoteRowView.self, in: evidence)
        #expect(rows.map(\.reviewerID) == reviewerIDs)
        #expect(!visibleFindingText(in: evidence).contains("removes the previous votes"))
        #expect(!visibleFindingText(in: evidence).contains("preserves the completed reports"))
        let missing = try #require(rows.first { $0.reviewerID == "peer-2" })
        #expect(missing.accessibilityRole() == .group)
        #expect(missing.accessibilityLabel()?.contains("Failed / no valid vote") == true)
        #expect(!missing.accessibilityPerformPress())
        let lead = try #require(rows.first { $0.reviewerID == "lead" })
        #expect(lead.accessibilityRole() == .button)
        #expect(lead.accessibilityLabel()?.contains("Show rationale") == true)
        #expect(lead.toolTip?.contains("removes the previous votes") == true)
        return lead
    }

    private func notProposedMarkdownRun() -> ReviewTeamRun {
        var run = pausedRun(phase: .crossChecking)
        run.phase = .staged
        let finding = ReviewCanonicalFinding(
            id: "markdown-finding", sourceCandidateIDs: ["lead:1", "peer:1"],
            path: "Alveary/Services/PullRequests/Collective/ReviewTeamCoordinator+CrossChecking.swift", line: 254, side: "RIGHT",
            body: """
            **Preserve the completed reports when retrying.** Calling `restartReview()` clears the saved votes before the failed worker resumes.

            A transient timeout can repeat completed inspections and replace findings that the user has already examined.

            Keep the completed reports and retry only the failed reviewer so the original majority requirement stays unchanged.
            """
        )
        run.canonical = ReviewCanonicalReport(findings: [finding])
        let votes = [
            ReviewTeamVote(voterID: "lead", findingID: finding.id, decision: .agree, priority: 1,
                           rationale: "`restartReview()` removes the previous votes before scheduling the retry."),
            ReviewTeamVote(voterID: "peer", findingID: finding.id, decision: .disagree, priority: nil,
                           rationale: "The caller uses **resumeReview()**, which preserves the completed reports.")
        ]
        run.voteReports = Dictionary(uniqueKeysWithValues: votes.map { ($0.voterID, ReviewVoteReport(votes: [$0])) })
        run.failures = ["crossChecking:peer-2": "The reviewer timed out without a valid response."]
        return run
    }

    private func visibleFindingText(in view: NSView) -> String {
        let fields = reviewTeamDescendants(of: NSTextField.self, in: view).filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.stringValue)
        let texts = reviewTeamDescendants(of: NSTextView.self, in: view).filter { !$0.isHiddenOrHasHiddenAncestor }.map(\.string)
        return (fields + texts).joined(separator: "\n")
    }
}
