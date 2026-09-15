import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollBridgeTests {
    func testSummaryPreparationAndEditorStayStableDuringTypingAndOtherUpdates() async throws {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: 700, height: 500))
        let window = NSWindow(contentRect: container.frame, styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = container
        container.layoutSubtreeIfNeeded()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let body = "Cold summary \(UUID().uuidString)\n\nSecond paragraph."
        let entry = HostToolWidgetEntry(
            id: "review", toolName: PullRequestHostToolCatalog.proposeReviewToolName,
            content: .pullRequestReviewProposal(ReviewProposalSnapshotFixture.widgetContent(commentIsProposed: false)),
            isComplete: true
        )
        var state = summaryState(body: body)
        var configuration = AppKitTranscriptRowFactory.Configuration(bubbleMaxWidth: 640)
        configuration.reviewProposalState = { _ in state }
        var preparedBodies: [String] = []
        coordinator.documentLoaderForTesting = { request in
            preparedBodies.append(request.markdown)
            return AppMarkdownParser().documentPreservingSource(for: request.markdown)
        }
        var items = (0..<159).map { ChatItem.transcriptNote(id: "note-\($0)", kind: .enteredPlanMode) }
        items.insert(.hostToolWidget(id: "review", entry: entry), at: 80)
        coordinator.update(container: container, items: items, rowConfiguration: configuration, isFollowing: false, scrollToBottomRequest: 0)
        let deadline = Date().addingTimeInterval(3)
        while container.rowFrame(for: "review") == nil, Date() < deadline { await Task.yield() }
        XCTAssertEqual(preparedBodies, [body])
        let row = try XCTUnwrap(ReviewSummaryTestFixture.descendant(in: container) { $0 is AppKitTranscriptHostToolWidgetRowView }
            as? AppKitTranscriptHostToolWidgetRowView)
        let summary = try XCTUnwrap(ReviewSummaryTestFixture.descendant(in: row) { $0 is AppKitReviewProposalSummaryView }
            as? AppKitReviewProposalSummaryView)
        let comment = try XCTUnwrap(ReviewSummaryTestFixture.descendant(in: row) { $0 is AppKitReviewProposalCommentCardView })
        let baseline = profileSummaryList(container)
        let editor = try await startSummaryEditing(summary, container: container, window: window)
        let text = try XCTUnwrap(window.firstResponder as? NSTextView)
        text.insertText("Typed locally", replacementRange: NSRange(location: 0, length: text.string.utf16.count))
        let selection = text.selectedRange()
        for _ in 0..<50 { await Task.yield() }
        XCTAssertTrue(window.firstResponder === text)
        state = summaryState(body: body, event: .comment)
        coordinator.update(container: container, items: items, rowConfiguration: configuration, isFollowing: false, scrollToBottomRequest: 0)
        XCTAssertEqual(preparedBodies, [body])
        XCTAssertTrue(summary.editor === editor)
        XCTAssertTrue(editor.draft.markdown.contains("Typed locally"))
        XCTAssertTrue(window.firstResponder === text)
        XCTAssertEqual(text.selectedRange(), selection)
        XCTAssertTrue(ReviewSummaryTestFixture.descendant(in: row) { $0 is AppKitReviewProposalCommentCardView } === comment)
        attachSummaryProfile(baseline: baseline, container: container)
        XCTAssertEqual(preparedBodies, [body])
        XCTAssertTrue(summary.editor === editor)
        summary.cancel()
        XCTAssertNil(summary.editor)
    }

    private func summaryState(body: String, event: PullRequestReviewEvent = .approve) -> ReviewProposalWidgetState {
        let presentation = PullRequestReviewProposalPresentation(
            id: ReviewProposalSnapshotFixture.proposalID, sourceConversationID: "source-conversation",
            identifier: ReviewProposalSnapshotFixture.identifier, title: "Review", proposedEvent: .approve,
            body: body, comments: [], pendingCommentCount: 2, createdAt: Date(timeIntervalSince1970: 1_000)
        )
        return ReviewProposalWidgetState(
            presentation: presentation, preview: .loaded(ReviewProposalSnapshotFixture.loadedPreview()),
            selectedEvent: event, canSubmit: true
        )
    }

    private func attachSummaryProfile(baseline: String, container: AppKitTranscriptScrollContainerView) {
        let editing = profileSummaryList(container)
        XCTContext.runActivity(named: "160-row scrolling and resizing profile") { activity in
            let attachment = XCTAttachment(string: "Before editing: \(baseline); while editing: \(editing).")
            attachment.lifetime = .keepAlways
            activity.add(attachment)
        }
    }

    private func startSummaryEditing(
        _ summary: AppKitReviewProposalSummaryView,
        container: AppKitTranscriptScrollContainerView, window: NSWindow
    ) async throws -> AppKitMarkdownEditor {
        XCTAssertTrue(container.scrollToRowTop(rowID: "review"))
        summary.beginEditing()
        let deadline = Date().addingTimeInterval(2)
        while !(window.firstResponder is NSTextView), Date() < deadline {
            window.displayIfNeeded()
            await Task.yield()
        }
        return try XCTUnwrap(summary.editor)
    }

    private func profileSummaryList(_ container: AppKitTranscriptScrollContainerView) -> String {
        var scrollTimes: [Double] = []
        var resizeTimes: [Double] = []
        for index in 0..<60 {
            let scrollStart = Date.timeIntervalSinceReferenceDate
            container.scrollView.contentView.scroll(to: NSPoint(x: 0, y: CGFloat(index * 71)))
            container.scrollView.reflectScrolledClipView(container.scrollView.contentView)
            container.layoutSubtreeIfNeeded()
            scrollTimes.append((Date.timeIntervalSinceReferenceDate - scrollStart) * 1_000)
            if index.isMultiple(of: 3) {
                let resizeStart = Date.timeIntervalSinceReferenceDate
                container.frame.size.width = index.isMultiple(of: 2) ? 700 : 620
                container.layoutSubtreeIfNeeded()
                resizeTimes.append((Date.timeIntervalSinceReferenceDate - resizeStart) * 1_000)
            }
        }
        return "Scroll total/max: \(scrollTimes.reduce(0, +))/\(scrollTimes.max() ?? 0) ms; "
            + "resize total/max: \(resizeTimes.reduce(0, +))/\(resizeTimes.max() ?? 0) ms (60 scrolls, 20 resizes)"
    }
}
