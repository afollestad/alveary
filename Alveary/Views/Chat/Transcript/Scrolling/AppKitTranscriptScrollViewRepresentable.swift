import AppKit
import SwiftUI

struct AppKitTranscriptScrollViewRepresentable: NSViewRepresentable {
    let items: [ChatItem]
    var transientRows = AppKitTranscriptTransientRows()
    var rowConfiguration = AppKitTranscriptRowFactory.Configuration()
    var isFollowing = true
    var scrollToBottomRequest = 0
    var onScrollMetricsChanged: (ChatTranscriptScrollMetrics) -> Void = { _ in }

    func makeCoordinator() -> AppKitTranscriptScrollBridgeCoordinator {
        AppKitTranscriptScrollBridgeCoordinator()
    }

    func makeNSView(context: Context) -> AppKitTranscriptScrollContainerView {
        AppKitTranscriptScrollContainerView()
    }

    func updateNSView(_ nsView: AppKitTranscriptScrollContainerView, context: Context) {
        context.coordinator.update(
            container: nsView,
            items: items,
            transientRows: transientRows,
            rowConfiguration: rowConfiguration,
            isFollowing: isFollowing,
            scrollToBottomRequest: scrollToBottomRequest,
            onScrollMetricsChanged: onScrollMetricsChanged
        )
    }
}

@MainActor
struct AppKitTranscriptTransientRows: Equatable {
    // Transient ids stay stable so live-only rows do not reset during bridge updates.
    static let thinkingRowID = "transient-thinking"
    static let streamingRowID = "streaming"
    static let interruptedRowID = "transient-interrupted"

    var isTurnActive = false
    var streamingText: String?
    var showsInterruptedNote = false
    var isThinkingAnimated = true
}

@MainActor
final class AppKitTranscriptScrollBridgeCoordinator {
    private let rowFactory = AppKitTranscriptRowFactory()
    private var lastScrollToBottomRequest: Int?

    func update(
        container: AppKitTranscriptScrollContainerView,
        items: [ChatItem],
        transientRows: AppKitTranscriptTransientRows = .init(),
        rowConfiguration: AppKitTranscriptRowFactory.Configuration,
        isFollowing: Bool,
        scrollToBottomRequest: Int,
        onScrollMetricsChanged: @escaping (ChatTranscriptScrollMetrics) -> Void = { _ in }
    ) {
        container.onScrollMetricsChanged = { metrics in
            DispatchQueue.main.async {
                onScrollMetricsChanged(metrics)
            }
        }
        var rowConfiguration = rowConfiguration
        let upstreamHeightInvalidated = rowConfiguration.onHeightInvalidated
        var pendingDirtyRowIDs: Set<String> = []
        var isBuildingRows = true
        rowConfiguration.onRowHeightInvalidated = { [weak container] rowID, animatesLayoutChanges in
            // Row configure can invalidate height before the new row list is installed;
            // batch those ids so the container never lays out the previous document.
            if isBuildingRows {
                pendingDirtyRowIDs.insert(rowID)
                return
            }
            container?.rowHeightInvalidated(
                rowID: rowID,
                // Row height callbacks can arrive after SwiftUI's `isFollowing`
                // snapshot was captured. Let the AppKit container gate bottom
                // preservation against its current scroll position instead.
                preserveBottomIfFollowing: true,
                animatesLayoutChanges: animatesLayoutChanges
            )
        }
        rowConfiguration.onHeightInvalidated = {
            upstreamHeightInvalidated()
        }

        let rows = rowFactory.makeRows(for: items, transientRows: transientRows, configuration: rowConfiguration)
        isBuildingRows = false
        container.configure(rows: rows, dirtyRowIDs: pendingDirtyRowIDs, preserveBottomIfFollowing: isFollowing)

        let shouldHonorScrollRequest = if let lastScrollToBottomRequest {
            lastScrollToBottomRequest != scrollToBottomRequest
        } else {
            scrollToBottomRequest != 0
        }

        if shouldHonorScrollRequest {
            container.scrollToBottom()
        }
        lastScrollToBottomRequest = scrollToBottomRequest
    }
}
