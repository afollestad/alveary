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

    private func host(
        for entry: HostToolWidgetEntry,
        onOpen: @escaping @MainActor (PullRequestIdentifier) -> Void = { _ in }
    ) -> NSView {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 640
        configuration.onOpenPullRequest = onOpen

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

    private func labels(in view: NSView) -> [String] {
        let own = (view as? NSTextField).map { [$0.stringValue] } ?? []
        return own + view.subviews.flatMap { labels(in: $0) }
    }

    private static let pullRequest = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
}
