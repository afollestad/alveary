import AppKit
import SwiftUI

struct AppKitTranscriptScrollViewRepresentable: NSViewRepresentable {
    let items: [ChatItem]
    var presentation: AppKitTranscriptPresentation?
    var transientRows = AppKitTranscriptTransientRows()
    var rowConfiguration = AppKitTranscriptRowFactory.Configuration()
    var isFollowing = true
    var scrollToBottomRequest = 0
    var scrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest?
    var onLoadingStateChanged: (Bool) -> Void = { _ in }
    var onScrollMetricsChanged: (ChatTranscriptScrollMetrics) -> Void = { _ in }

    func makeCoordinator() -> AppKitTranscriptScrollBridgeCoordinator {
        AppKitTranscriptScrollBridgeCoordinator()
    }

    func makeNSView(context: Context) -> AppKitTranscriptScrollContainerView {
        AppKitTranscriptScrollContainerView()
    }

    static func dismantleNSView(_ nsView: AppKitTranscriptScrollContainerView, coordinator: AppKitTranscriptScrollBridgeCoordinator) {
        coordinator.cancel(container: nsView)
    }

    func updateNSView(_ nsView: AppKitTranscriptScrollContainerView, context: Context) {
        context.coordinator.update(
            container: nsView,
            items: items,
            presentation: presentation,
            transientRows: transientRows,
            rowConfiguration: rowConfiguration,
            isFollowing: isFollowing,
            scrollToBottomRequest: scrollToBottomRequest,
            scrollToRowTopRequest: scrollToRowTopRequest,
            onLoadingStateChanged: onLoadingStateChanged,
            onScrollMetricsChanged: onScrollMetricsChanged
        )
    }
}

struct AppKitTranscriptRowTopScrollRequest: Equatable {
    let id: Int
    let rowID: String
    let topInset: CGFloat
}

@MainActor
struct AppKitTranscriptTransientRows: Equatable {
    // Transient ids stay stable so live-only rows do not reset during bridge updates.
    static let thinkingRowID = "transient-thinking"
    static let streamingRowID = "streaming"
    static let interruptedRowID = "transient-interrupted"
    static let thoughtRowIDPrefix = "transient-thought-"

    var isTurnActive = false
    var isAwaitingExitPlanModeFollowUp = false
    var streamingText: String?
    var thoughtText: String?
    var thoughtSequence = 0
    var completedThoughtText: String?
    var completedThoughtSequence = 0
    var showsInterruptedNote = false
    var isThinkingAnimated = true

    static func thoughtRowID(sequence: Int) -> String {
        "\(thoughtRowIDPrefix)\(sequence)"
    }

    static func isThoughtRowID(_ rowID: String) -> Bool {
        rowID.hasPrefix(thoughtRowIDPrefix)
    }
}
