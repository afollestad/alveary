import AppKit
import XCTest

@testable import Alveary

/// Drives the real row factory, because a thread card's only action is the card itself: the
/// press has to reach the configuration handler through the widget shell.
@MainActor
final class ThreadActionWidgetRowTests: XCTestCase {
    func testCreatedCardOpensItsThread() throws {
        var opened: [String] = []
        let host = host(for: entry(action: .create, status: .applied)) { opened.append($0) }

        XCTAssertTrue(labels(in: host).contains("Thread created: Add caching"))
        let card = try XCTUnwrap(pressableCard(in: host), "Expected the card itself to be pressable")
        XCTAssertTrue(card.accessibilityPerformPress())

        XCTAssertEqual(opened, ["conv-1"])
    }

    /// An archived thread is still reachable — the root routes it to the Archived screen — so
    /// the card stays a control.
    func testArchivedCardStillOpensItsThread() throws {
        var opened: [String] = []
        let host = host(for: entry(action: .archive, status: .applied)) { opened.append($0) }

        XCTAssertTrue(labels(in: host).contains("Thread archived: Add caching"))
        _ = try XCTUnwrap(pressableCard(in: host)).accessibilityPerformPress()

        XCTAssertEqual(opened, ["conv-1"])
    }

    func testRunningCardIsNotPressableYet() {
        let host = host(for: entry(action: .pin, status: .running))

        XCTAssertTrue(labels(in: host).contains("Pinning thread…"))
        XCTAssertNil(pressableCard(in: host))
    }

    /// A refused call changed nothing, so the card must not offer a thread it may not have.
    func testFailedCardIsNotPressable() {
        let host = host(for: entry(action: .pin, status: .failed, isError: true))

        XCTAssertTrue(labels(in: host).contains("Could not pin the thread"))
        XCTAssertNil(pressableCard(in: host))
    }

    /// A text-fallback result that never named a thread has nothing to open.
    func testCardWithoutAThreadIsNotPressable() {
        let host = host(for: entry(action: .create, status: .applied, threadID: nil))

        XCTAssertTrue(labels(in: host).contains("Thread created: Add caching"))
        XCTAssertNil(pressableCard(in: host))
    }

    private func host(
        for entry: HostToolWidgetEntry,
        onOpen: @escaping @MainActor (String) -> Void = { _ in }
    ) -> NSView {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = 640
        configuration.onOpenThread = onOpen

        let factory = AppKitTranscriptRowFactory()
        let item = ChatItem.hostToolWidget(id: "host-tool-thread", entry: entry)
        let host = NSView(frame: NSRect(x: 0, y: 0, width: 640, height: 200))
        for row in factory.makeRows(for: [item], configuration: configuration) {
            row.view.frame = NSRect(x: 0, y: 0, width: 640, height: 200)
            host.addSubview(row.view)
        }
        host.layoutSubtreeIfNeeded()
        return host
    }

    private func entry(
        action: ThreadActionWidgetContent.Action,
        status: ThreadActionWidgetContent.Status,
        threadID: String? = "conv-1",
        isError: Bool = false
    ) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-thread",
            toolName: ThreadHostToolCatalog.pinThreadToolName,
            content: .threadAction(
                ThreadActionWidgetContent(
                    action: action,
                    threadID: threadID,
                    name: "Add caching",
                    projectPath: nil,
                    message: "Done.",
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
}
