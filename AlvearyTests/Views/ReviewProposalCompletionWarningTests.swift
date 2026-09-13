import AppKit
import Foundation
import Testing

@testable import Alveary

@MainActor
struct ReviewProposalCompletionWarningTests {
    @Test(arguments: [true, false], [true, false])
    func `completion warning belongs only to the matching collective proposal`(isCollective: Bool, matchesRun: Bool) throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .staged
        run.inspections = Dictionary(uniqueKeysWithValues: run.team.map { ($0.id, ReviewInspectionReport(findings: [])) })
        run.canonical = ReviewCanonicalReport(findings: [ReviewCoordinatorWorker.canonicalFinding])
        run.voteReports = Dictionary(uniqueKeysWithValues: run.team.prefix(2).map { ($0.id, ReviewVoteReport(votes: [])) })
        run.failures["crossChecking:peer-2"] = "Timed out after 300 seconds"
        try fixture.coordinator.persist(run)
        let record = PullRequestReviewProposalRecord(
            payloadVersion: 4, id: matchesRun ? run.proposalID : "another-proposal", deduplicationKey: "dedup",
            repositoryNameWithOwner: run.identifier.nameWithOwner, number: run.identifier.number,
            event: "approve", body: nil, comments: [], titleSnapshot: "PR title", pendingCommentCountSnapshot: 0,
            sourceProviderID: nil, sourceProcessToken: nil, sourceRequestID: nil,
            sourceKind: isCollective ? .collectiveReview : .hostTool, sourceRunID: run.id, createdAt: .now
        )
        try fixture.conversation.storePullRequestReviewProposal(record)
        try fixture.container.mainContext.save()
        let storedProposal = fixture.conversation.pullRequestReviewProposalJSON
        let coordinator = PullRequestReviewProposalCoordinator(
            modelContext: fixture.container.mainContext, pullRequestsService: fixture.service
        )

        let presentation = try #require(coordinator.presentation(forProposalID: record.id))

        #expect(presentation.collectiveCompletionWarning == (isCollective && matchesRun ? Self.warning : nil))
        #expect(presentation.proposedEvent == .approve)
        #expect(presentation.body == nil)
        #expect(fixture.conversation.pullRequestReviewProposalJSON == storedProposal)
        #expect(fixture.service.detailCallCount == 0)
    }

    @Test
    func `partial completion warning is readable and approval remains available`() throws {
        let view = AppKitReviewProposalWidgetView()
        view.configure(configuration(warning: Self.warning))

        let warning = try #require(labels(in: view).first { $0.stringValue == Self.warning })
        let control = try #require(descendant(AppKitTranscriptApprovalSplitControl.self, in: view))
        #expect(warning.textColor == .labelColor)
        #expect(warning.accessibilityLabel() == Self.warning)
        #expect(warning.maximumNumberOfLines == 0)
        #expect(control.isEnabled(forSegment: 0))
        #expect(control.label(forSegment: 0) == "Approve")

        view.configure(configuration(warning: nil))

        #expect(!labels(in: view).contains { $0.stringValue == Self.warning })
    }

    private func configuration(warning: String?) -> AppKitReviewProposalWidgetView.Configuration {
        .init(
            content: ReviewProposalSnapshotFixture.widgetContent(commentIsProposed: false),
            presentation: ReviewProposalSnapshotFixture.presentation(collectiveCompletionWarning: warning),
            preview: .loading, selectedEvent: .approve, canSubmit: true, isInteractive: true, isSubmitting: false,
            outcome: nil, errorMessage: nil, typography: TranscriptTypography()
        )
    }

    private func labels(in view: NSView) -> [NSTextField] {
        let own = (view as? NSTextField).map { [$0] } ?? []
        return own + view.subviews.flatMap { labels(in: $0) }
    }

    private func descendant<T: NSView>(_ type: T.Type, in view: NSView) -> T? {
        if let match = view as? T { return match }
        return view.subviews.lazy.compactMap { descendant(type, in: $0) }.first
    }

    private static let warning = "Partial team review: 2/3 cross-checks completed. The proposal uses a fixed majority, not unanimous agreement."
}
