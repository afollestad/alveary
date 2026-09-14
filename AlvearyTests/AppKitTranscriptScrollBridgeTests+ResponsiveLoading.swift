@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTranscriptScrollBridgeTests {
    func testDelayedInitialLoadingKeepsLatestGeometryAndBottomRequest() async throws {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let loader = ControlledTranscriptDocumentLoader()
        defer { loader.releaseAll() }
        coordinator.documentLoaderForTesting = loader.load
        let items = loadingItems()
        coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        await loader.waitForRequest()
        let initialHeight = container.documentHeight
        // Longer than the UI's settling watchdog: history has not satisfied the request yet.
        try await Task.sleep(for: .milliseconds(450))
        XCTAssertTrue(container.isLoadingForTesting)
        XCTAssertEqual(container.documentHeight, initialHeight, accuracy: 0.5)
        XCTAssertNil(container.rowFrame(for: "loading"))

        container.frame.size = NSSize(width: 180, height: 90)
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        var settings = AppSettings()
        settings.chatFontSize = 20
        coordinator.update(container: container, items: items,
                           rowConfiguration: .init(bubbleMaxWidth: 160, typography: TranscriptTypography(settings: settings)),
                           isFollowing: true, scrollToBottomRequest: 3)
        XCTAssertEqual(loader.requestCount, 1)
        loader.releaseAll()
        await waitForLoadingToFinish(coordinator)

        XCTAssertFalse(container.isLoadingForTesting)
        XCTAssertEqual(container.transcriptDocumentView.frame.width, 180, accuracy: 0.5)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
        XCTAssertGreaterThan(try XCTUnwrap(container.rowFrame(for: "loading")).height, 90)
        let row = try XCTUnwrap(container.transcriptDocumentView.subviews.compactMap { $0 as? AppKitTranscriptTextBubbleRowView }.first)
        XCTAssertEqual(row.configuration?.typography.body.pointSize, 20)
    }

    func testPendingPreparationCannotReplaceRevertedContent() async {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let loader = ControlledTranscriptDocumentLoader()
        defer { loader.releaseAll() }
        coordinator.documentLoaderForTesting = loader.load
        let original: [ChatItem] = [.transcriptNote(id: "original", kind: .enteredPlanMode)]
        coordinator.update(container: container, items: original, rowConfiguration: .init(), isFollowing: false, scrollToBottomRequest: 0)
        coordinator.update(container: container, items: loadingItems(), rowConfiguration: .init(),
                           isFollowing: false, scrollToBottomRequest: 0)
        await loader.waitForRequest()
        coordinator.update(container: container, items: original, rowConfiguration: .init(), isFollowing: false, scrollToBottomRequest: 0)
        loader.releaseAll()
        await loader.waitForCompletion()
        XCTAssertNotNil(container.rowFrame(for: "original"))
        XCTAssertNil(container.rowFrame(for: "loading"))
        XCTAssertFalse(container.isLoadingForTesting)
    }

    func testLoadingToEmptyCancelsObsoleteHistoryAndClearsLoader() async {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let loader = ControlledTranscriptDocumentLoader()
        defer { loader.releaseAll() }
        coordinator.documentLoaderForTesting = loader.load
        coordinator.update(container: container, items: loadingItems(), rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        await loader.waitForRequest()
        coordinator.update(container: container, items: [], rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        loader.releaseAll()
        await loader.waitForCompletion()
        XCTAssertFalse(container.isLoadingForTesting)
        XCTAssertNil(container.rowFrame(for: "loading"))
        XCTAssertEqual(container.scrollOffsetY, 0, accuracy: 0.5)
        XCTAssertLessThan(container.documentHeight, container.bounds.height)
    }

    func testPreparationRetainsMoreDocumentsThanSharedCacheUntilRealWidthArrives() async {
        let container = loadingContainer(width: 0)
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let token = UUID().uuidString
        let items = (0..<245).map { ChatItem.assistantMessage(id: "retained-\($0)", text: "\(token) document \($0)") }
        var preparedCount = 0
        // Deliberately do not populate the global cache: the installed shells must use the
        // exact retained results, even when every global entry has been evicted.
        coordinator.documentLoaderForTesting = { request in
            preparedCount += 1
            return AppMarkdownParser().documentPreservingSource(for: request.markdown)
        }
        coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        for _ in 0..<100 where preparedCount < items.count { await Task.yield() }
        XCTAssertEqual(preparedCount, items.count)
        XCTAssertTrue(container.isLoadingForTesting)
        XCTAssertNil(container.rowFrame(for: "retained-0"))

        container.frame.size.width = 320
        container.needsLayout = true
        container.layoutSubtreeIfNeeded()
        await waitForLoadingToFinish(coordinator)
        let rows = container.transcriptDocumentView.subviews.compactMap { $0 as? AppKitTranscriptTextBubbleRowView }
        XCTAssertEqual(rows.count, 245)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.synchronousDocumentParseCountForTesting }, 0)
        XCTAssertFalse(container.isLoadingForTesting)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testDismantledTranscriptRejectsPendingDocuments() async {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let loader = ControlledTranscriptDocumentLoader()
        defer { loader.releaseAll() }
        coordinator.documentLoaderForTesting = loader.load
        coordinator.update(container: container, items: loadingItems(), rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        await loader.waitForRequest()
        coordinator.cancel(container: container)
        loader.releaseAll()
        await loader.waitForCompletion()
        XCTAssertNil(container.rowFrame(for: "loading"))
        XCTAssertFalse(container.isLoadingForTesting)
    }

    func testUserScrollDuringPreparationCancelsEarlierBottomRequest() async {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let loader = ControlledTranscriptDocumentLoader()
        defer { loader.releaseAll() }
        coordinator.documentLoaderForTesting = loader.load
        let original = (0..<30).map { ChatItem.transcriptNote(id: "note-\($0)", kind: .enteredPlanMode) }
        coordinator.update(container: container, items: original, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        let replacement = original + loadingItems()
        coordinator.update(container: container, items: replacement, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 2)
        await loader.waitForRequest()
        container.scrollContentView(toY: 20)
        coordinator.update(container: container, items: replacement, rowConfiguration: .init(), isFollowing: false, scrollToBottomRequest: 2)
        loader.releaseAll()
        for _ in 0..<100 where container.rowFrame(for: "loading") == nil { await Task.yield() }
        XCTAssertNotNil(container.rowFrame(for: "loading"))
        XCTAssertEqual(container.scrollOffsetY, 20, accuracy: 0.5)
        XCTAssertLessThan(container.visibleBottomY, container.documentHeight)
    }

    func testUserScrollWhileWarmUpdateWaitsForAnimationCancelsEarlierBottomRequest() {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let original = (0..<30).map { ChatItem.transcriptNote(id: "note-\($0)", kind: .enteredPlanMode) }
        coordinator.update(container: container, items: original, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        container.activeScrollAnimationToken = UUID()
        let replacement = original + [.transcriptNote(id: "new", kind: .enteredPlanMode)]
        coordinator.update(container: container, items: replacement, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 2)
        XCTAssertNil(container.rowFrame(for: "new"))

        container.scrollContentView(toY: 20)
        coordinator.update(container: container, items: replacement, rowConfiguration: .init(), isFollowing: false, scrollToBottomRequest: 2)
        container.activeScrollAnimationToken = nil
        container.notifyStableLayoutIfNeeded()

        XCTAssertNotNil(container.rowFrame(for: "new"))
        XCTAssertEqual(container.scrollOffsetY, 20, accuracy: 0.5)
    }

    func testNewRowTopRequestWhileCancellingFollowRemainsPending() throws {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let original = (0..<30).map { ChatItem.transcriptNote(id: "note-\($0)", kind: .enteredPlanMode) }
        coordinator.update(container: container, items: original, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        container.activeScrollAnimationToken = UUID()
        let replacement = original + [.transcriptNote(id: "new", kind: .enteredPlanMode)]
        coordinator.update(container: container, items: replacement, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 2)
        coordinator.update(container: container, items: replacement, rowConfiguration: .init(), isFollowing: false,
                           scrollToBottomRequest: 2, scrollToRowTopRequest: .init(id: 1, rowID: "note-5", topInset: 0))
        container.activeScrollAnimationToken = nil
        container.notifyStableLayoutIfNeeded()

        XCTAssertEqual(container.scrollOffsetY, try XCTUnwrap(container.rowFrame(for: "note-5")).minY, accuracy: 0.5)
    }

    func testTransientOnlyContentHonorsBottomScrollRequest() {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let transient = AppKitTranscriptTransientRows(isTurnActive: true, streamingText: String(repeating: "Streaming line\n", count: 30))
        coordinator.update(container: container, items: [], transientRows: transient, rowConfiguration: .init(),
                           isFollowing: false, scrollToBottomRequest: 0)
        container.scrollContentView(toY: 0)
        coordinator.update(container: container, items: [], transientRows: transient, rowConfiguration: .init(),
                           isFollowing: false, scrollToBottomRequest: 1)

        XCTAssertGreaterThan(container.scrollOffsetY, 0)
        XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
    }

    func testUnchangedContentDefersNewBottomRequestUntilAnimationsSettle() {
        for usesClipAnimation in [false, true] {
            let container = loadingContainer()
            let coordinator = AppKitTranscriptScrollBridgeCoordinator()
            let items = (0..<30).map { ChatItem.transcriptNote(id: "note-\($0)", kind: .enteredPlanMode) }
            coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: false, scrollToBottomRequest: 0)
            container.scrollContentView(toY: 20)
            container.transcriptDocumentView.hasActiveFrameAnimation = !usesClipAnimation
            container.activeScrollAnimationToken = usesClipAnimation ? UUID() : nil

            coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
            XCTAssertEqual(container.scrollOffsetY, 20, accuracy: 0.5)
            container.transcriptDocumentView.hasActiveFrameAnimation = false
            container.activeScrollAnimationToken = nil
            container.notifyStableLayoutIfNeeded()

            XCTAssertEqual(container.visibleBottomY, container.documentHeight, accuracy: 0.5)
        }
    }

    func testUnchangedContentDefersNewRowTopRequestUntilAnimationSettles() throws {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<30).map { ChatItem.transcriptNote(id: "note-\($0)", kind: .enteredPlanMode) }
        coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: false, scrollToBottomRequest: 0)
        container.activeScrollAnimationToken = UUID()
        coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: false,
                           scrollToBottomRequest: 0, scrollToRowTopRequest: .init(id: 1, rowID: "note-5", topInset: 0))
        XCTAssertEqual(container.scrollOffsetY, 0, accuracy: 0.5)
        container.activeScrollAnimationToken = nil
        container.notifyStableLayoutIfNeeded()

        XCTAssertEqual(container.scrollOffsetY, try XCTUnwrap(container.rowFrame(for: "note-5")).minY, accuracy: 0.5)
    }

    func testFollowingCancellationInvalidatesCapturedClipAnimationOffset() async throws {
        let container = loadingContainer()
        let coordinator = AppKitTranscriptScrollBridgeCoordinator()
        let items = (0..<30).map { ChatItem.transcriptNote(id: "note-\($0)", kind: .enteredPlanMode) }
        coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: true, scrollToBottomRequest: 1)
        container.animateDocumentHeightAndScroll(to: container.transcriptDocumentView.frame.size, targetScrollY: 200)
        container.scrollContentView(toY: 20)
        coordinator.update(container: container, items: items, rowConfiguration: .init(), isFollowing: false, scrollToBottomRequest: 1)
        XCTAssertNil(container.activeScrollAnimationToken)

        try await Task.sleep(for: .seconds(appExpansionAnimationDuration + 0.1))
        XCTAssertEqual(container.scrollOffsetY, 20, accuracy: 0.5)
    }

    private func loadingContainer(width: CGFloat = 320) -> AppKitTranscriptScrollContainerView {
        let container = AppKitTranscriptScrollContainerView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        container.layoutSubtreeIfNeeded()
        return container
    }

    private func loadingItems() -> [ChatItem] {
        [.assistantMessage(id: "loading", text: UUID().uuidString + String(repeating: " long wrapping content", count: 100))]
    }

    private func waitForLoadingToFinish(_ coordinator: AppKitTranscriptScrollBridgeCoordinator) async {
        for _ in 0..<100 where coordinator.isPreparingInitialContent { await Task.yield() }
    }
}

@MainActor
private final class ControlledTranscriptDocumentLoader {
    private var continuations: [CheckedContinuation<Void, Never>] = []
    private(set) var requestCount = 0
    private(set) var completionCount = 0

    func load(_ request: AppKitTranscriptMarkdownPrepRequest) async -> AppMarkdownDocument {
        requestCount += 1
        await withCheckedContinuation { continuations.append($0) }
        completionCount += 1
        return AppMarkdownParser().documentPreservingSource(for: request.markdown)
    }

    func releaseAll() {
        let pending = continuations
        continuations.removeAll()
        pending.forEach { $0.resume() }
    }

    func waitForRequest() async {
        for _ in 0..<100 where requestCount == 0 { await Task.yield() }
    }

    func waitForCompletion() async {
        for _ in 0..<100 where completionCount < requestCount { await Task.yield() }
    }
}
