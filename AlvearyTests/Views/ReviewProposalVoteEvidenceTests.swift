import AppKit
import Testing

@testable import Alveary

@MainActor
struct ReviewProposalVoteEvidenceTests {
    @Test(arguments: [ReviewTeamVote.Decision.agree, .disagree, .abstain])
    func `each decision uses readable wrapping Markdown for its rationale`(decision: ReviewTeamVote.Decision) throws {
        let view = AppKitReviewProposalVoteEvidenceView()
        let vote = ReviewTeamVote(
            voterID: "lead",
            findingID: "finding",
            decision: decision,
            priority: decision == .agree ? 2 : nil,
            rationale: "The **retry** path in `Retry.swift` keeps running after cancellation."
        )
        view.configure(
            findingID: "finding",
            votes: [vote],
            reviewers: reviewers,
            typography: TranscriptTypography(),
            initiallyExpanded: true
        )

        let fields = descendants(of: NSTextField.self, in: view)
        let rationale = try #require(fields.first { $0.stringValue.hasPrefix("The retry path") })
        let attributed = rationale.attributedStringValue
        let codeRange = (attributed.string as NSString).range(of: "Retry.swift")
        try #require(codeRange.location != NSNotFound)
        let paragraphStyle = try #require(attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)
        #expect(attributed.string == "The retry path in Retry.swift keeps running after cancellation.")
        #expect(attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor == .labelColor)
        #expect(attributed.attribute(.backgroundColor, at: codeRange.location, effectiveRange: nil) != nil)
        #expect(paragraphStyle.lineBreakMode == .byWordWrapping)
        #expect(rationale.maximumNumberOfLines == 0)
        #expect(rationale.accessibilityLabel() == attributed.string)
        #expect(fields.contains { $0.stringValue == "Lead reviewer" })
        #expect(fields.contains { $0.stringValue == "Requested model: codex · gpt-5.6-sol" })
        #expect(fields.contains { $0.stringValue == (decision == .agree ? "Agree · P2" : decision.rawValue.capitalized) })
    }

    @Test func `missing votes retain a separate reviewer identity and failure status`() {
        let view = AppKitReviewProposalVoteEvidenceView()
        view.configure(
            findingID: "finding",
            votes: [],
            reviewers: reviewers,
            typography: TranscriptTypography(),
            initiallyExpanded: true
        )

        let groups = descendants(of: NSStackView.self, in: view).compactMap { $0.accessibilityLabel() }
        #expect(groups.contains("Lead reviewer, Failed / no valid vote. Requested model: codex · gpt-5.6-sol"))
        #expect(groups.contains("Reviewer 2, Failed / no valid vote. Requested model: claude · claude-fable-5-1"))
    }

    @Test func `vote expansion survives restyling and invalidates height in both directions`() throws {
        let view = AppKitReviewProposalVoteEvidenceView()
        var invalidations = 0
        view.onHeightInvalidated = { invalidations += 1 }
        view.configure(findingID: "finding", votes: [], reviewers: reviewers, typography: TranscriptTypography())
        try #require(descendants(of: NSButton.self, in: view).first).performClick(nil)
        #expect(invalidations == 1)

        var settings = AppSettings()
        settings.chatFontSize = 18
        view.configure(findingID: "finding", votes: [], reviewers: reviewers, typography: TranscriptTypography(settings: settings))

        let collapse = try #require(descendants(of: NSButton.self, in: view).first)
        #expect(collapse.accessibilityLabel() == "0 of 2 reviewers agreed. Hide vote details")
        collapse.performClick(nil)
        #expect(invalidations == 2)
        #expect(descendants(of: NSTextField.self, in: view).isEmpty)

        view.configure(findingID: "different-finding", votes: [], reviewers: reviewers, typography: TranscriptTypography())
        #expect(descendants(of: NSButton.self, in: view).first?.accessibilityLabel() == "0 of 2 reviewers agreed. Show vote details")
    }

    private var reviewers: [PullRequestReviewProposalRecord.Reviewer] {
        [
            PullRequestReviewProposalRecord.Reviewer(id: "lead", providerID: "codex", modelOptionID: "gpt-5.6-sol"),
            PullRequestReviewProposalRecord.Reviewer(id: "peer", providerID: "claude", modelOptionID: "claude-fable-5-1")
        ]
    }

    private func descendants<View: NSView>(of type: View.Type, in view: NSView) -> [View] {
        view.subviews.flatMap { subview in
            let nested = descendants(of: type, in: subview)
            return (subview as? View).map { [$0] + nested } ?? nested
        }
    }
}
