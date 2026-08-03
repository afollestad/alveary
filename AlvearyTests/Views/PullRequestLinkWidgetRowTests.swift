import AppKit
import XCTest

@testable import Alveary

/// Drives the real row factory, because a link card's only action is the card itself: the
/// press has to reach the configuration handler through the widget shell.
@MainActor
final class PullRequestLinkWidgetRowTests: XCTestCase {
    func testLinkedCardOpensItsPullRequest() throws {
        var opened: [PullRequestIdentifier] = []
        let host = host(for: entry(status: .applied)) { opened.append($0) }

        XCTAssertTrue(labels(in: host).contains("PR linked to thread: octo/alpha#7"))
        let card = try XCTUnwrap(pressableCard(in: host), "Expected the card itself to be pressable")
        XCTAssertTrue(card.accessibilityPerformPress())

        XCTAssertEqual(opened, [Self.pullRequest])
    }

    /// An unlink card still opens the pull request; only Alveary's record changed.
    func testUnlinkedCardOpensItsPullRequest() throws {
        var opened: [PullRequestIdentifier] = []
        let host = host(for: entry(action: .unlink, status: .applied)) { opened.append($0) }

        XCTAssertTrue(labels(in: host).contains("PR unlinked from thread: octo/alpha#7"))
        _ = try XCTUnwrap(pressableCard(in: host)).accessibilityPerformPress()

        XCTAssertEqual(opened, [Self.pullRequest])
    }

    func testRunningCardIsNotPressableYet() {
        let host = host(for: entry(status: .running))

        XCTAssertTrue(labels(in: host).contains("Linking pull request…"))
        XCTAssertNil(pressableCard(in: host))
    }

    /// A refused call has no pull request to open, so the card must not offer one.
    func testFailedCardIsNotPressable() {
        let host = host(for: entry(status: .failed, isError: true))

        XCTAssertTrue(labels(in: host).contains("Could not link the pull request"))
        XCTAssertNil(pressableCard(in: host))
    }

    /// The fetch behind an unlinked pull request is a GitHub round trip, so the card has to show
    /// the wait — and only the card that asked for it.
    func testCardWaitingOnItsPullRequestSpinsInsteadOfShowingTheChevron() {
        let waiting = host(for: entry(status: .applied), pendingLookup: Self.pullRequest)
        XCTAssertEqual(animatingSpinnerCount(in: waiting), 1)

        let idle = host(for: entry(status: .applied))
        XCTAssertEqual(animatingSpinnerCount(in: idle), 0)

        let otherPullRequest = host(
            for: entry(status: .applied),
            pendingLookup: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 9)
        )
        XCTAssertEqual(animatingSpinnerCount(in: otherPullRequest), 0)
    }

    /// Swapping the chevron for the spinner must not resize the card under the pointer — in
    /// either axis, since a taller card also shifts every row beneath it.
    func testWaitingDoesNotResizeTheCard() throws {
        let idle = try XCTUnwrap(cardFrame(in: host(for: entry(status: .applied))))
        let waiting = try XCTUnwrap(
            cardFrame(in: host(for: entry(status: .applied), pendingLookup: Self.pullRequest))
        )
        XCTAssertEqual(idle.width, waiting.width, accuracy: 0.5)
        XCTAssertEqual(idle.height, waiting.height, accuracy: 0.5)
    }

    private func host(
        for entry: HostToolWidgetEntry,
        pendingLookup: PullRequestIdentifier? = nil,
        onOpen: @escaping @MainActor (PullRequestIdentifier) -> Void = { _ in }
    ) -> NSView {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 640
        configuration.onOpenPullRequest = onOpen
        configuration.pendingPullRequestLookup = pendingLookup

        let factory = AppKitTranscriptRowFactory()
        let item = ChatItem.hostToolWidget(id: "host-tool-link", entry: entry)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 200))
        for row in factory.makeRows(for: [item], configuration: configuration) {
            row.view.frame = NSRect(x: 0, y: 0, width: 640, height: 200)
            host.addSubview(row.view)
        }
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func entry(
        action: PullRequestLinkWidgetContent.Action = .link,
        status: PullRequestLinkWidgetContent.Status,
        isError: Bool = false
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-link",
            toolName: ThreadHostToolCatalog.linkPullRequestToolName,
            content: .pullRequestLink(
                PullRequestLinkWidgetContent(
                    action: action,
                    identifier: Self.pullRequest,
                    title: "Add caching",
                    message: "Linked it.",
                    status: status
                )
            ),
            isComplete: status != .running,
            isError: isError
        )
    }

    /// The shell marks the card a button only while it can open something, so the role is
    /// what the press has to be sent through.
    private func pressableCard(in view: NSView) -> NSView? {
        if view.accessibilityRole() == .button {
            return view
        }
        for subview in view.subviews {
            if let card = pressableCard(in: subview) {
                return card
            }
        }
        return nil
    }

    /// The spinner is inserted only while waiting, so its presence is the whole assertion.
    private func animatingSpinnerCount(in view: NSView) -> Int {
        let own = view is AppKitStatusIndicatorSpinner ? 1 : 0
        return own + view.subviews.reduce(0) { $0 + animatingSpinnerCount(in: $1) }
    }

    /// The bubble is the laid-out card inside the row, which itself fills the transcript.
    private func cardFrame(in view: NSView) -> NSRect? {
        pressableCard(in: view)?.frame
    }

    private func labels(in view: NSView) -> [String] {
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap { labels(in: $0) }
    }

    private static let pullRequest = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
}
