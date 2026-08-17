import AppKit
import XCTest

@testable import Alveary

/// Drives the real row factory, because the refusal a card shows is assembled from two independent
/// sources — the shell's detail line and the card's own banner stack — and only the built row shows
/// how many times the message actually reaches the screen.
@MainActor
final class ReviewProposalWidgetRowTests: XCTestCase {
    /// GitHub refuses approving your own pull request, and the card has to say so exactly once.
    /// The shell's detail line owns a refusal (`HostToolWidgetSummary.detail(for:)` hands it the
    /// message on `.failed`), so the banner stack must not repeat it.
    func testARefusalIsStatedOnce() {
        let host = host(for: entry(status: .failed, isError: true))

        XCTAssertTrue(labels(in: host).contains(Self.refusal))
        XCTAssertEqual(labels(in: host).filter { $0 == Self.refusal }.count, 1)
    }

    func testARefusalKeepsItsSummaryLine() {
        let host = host(for: entry(status: .failed, isError: true))

        XCTAssertTrue(labels(in: host).contains("Could not prepare the review"))
    }

    private func host(for entry: HostToolWidgetEntry) -> NSView {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 640

        let factory = AppKitTranscriptRowFactory()
        let item = ChatItem.hostToolWidget(id: "host-tool-review-proposal", entry: entry)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 400))
        for row in factory.makeRows(for: [item], configuration: configuration) {
            row.view.frame = NSRect(x: 0, y: 0, width: 640, height: 400)
            host.addSubview(row.view)
        }
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func entry(
        status: PullRequestReviewProposalWidgetContent.Status,
        isError: Bool = false
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-propose-review",
            toolName: PullRequestHostToolCatalog.proposeReviewToolName,
            content: .pullRequestReviewProposal(
                PullRequestReviewProposalWidgetContent(
                    event: .approve,
                    identifier: Self.pullRequest,
                    body: nil,
                    commentCount: nil,
                    pendingCommentCount: nil,
                    proposalID: nil,
                    message: Self.refusal,
                    status: status
                )
            ),
            isComplete: status != .running,
            isError: isError
        )
    }

    private func labels(in view: NSView) -> [String] {
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap { labels(in: $0) }
    }

    private static let pullRequest = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    private static let refusal = """
        GitHub does not accept approving or requesting changes on the user's own pull request. \
        Propose a comment review instead.
        """
}
