import AppKit
import SwiftUI

struct AppKitTranscriptScrollViewRepresentable: NSViewRepresentable {
    let items: [ChatItem]
    var transientRows = AppKitTranscriptTransientRows()
    var rowConfiguration = AppKitTranscriptRowFactory.Configuration()
    var isFollowing = true
    var scrollToBottomRequest = 0
    var scrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest?
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
            scrollToRowTopRequest: scrollToRowTopRequest,
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

    var isTurnActive = false
    var isAwaitingExitPlanModeFollowUp = false
    var streamingText: String?
    var showsInterruptedNote = false
    var isThinkingAnimated = true
}

@MainActor
final class AppKitTranscriptScrollBridgeCoordinator {
    private let rowFactory = AppKitTranscriptRowFactory()
    private var lastScrollToBottomRequest: Int?
    private var lastScrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest?
    private var lastAppliedContentSignature: AppKitTranscriptPreparedUpdate.ContentSignature?
    private var markdownPreparationGeneration = 0
    private var markdownPreparationTask: Task<Void, Never>?
    private var currentIsFollowing = true

    deinit {
        markdownPreparationTask?.cancel()
    }

    func update(
        container: AppKitTranscriptScrollContainerView,
        items: [ChatItem],
        transientRows: AppKitTranscriptTransientRows = .init(),
        rowConfiguration: AppKitTranscriptRowFactory.Configuration,
        isFollowing: Bool,
        scrollToBottomRequest: Int,
        scrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest? = nil,
        onScrollMetricsChanged: @escaping (ChatTranscriptScrollMetrics) -> Void = { _ in }
    ) {
        currentIsFollowing = isFollowing
        container.onScrollMetricsChanged = { metrics in
            DispatchQueue.main.async {
                onScrollMetricsChanged(metrics)
            }
        }
        let update = AppKitTranscriptPreparedUpdate(
            items: items,
            transientRows: transientRows,
            rowConfiguration: rowConfiguration,
            isFollowing: isFollowing,
            scrollToBottomRequest: scrollToBottomRequest,
            scrollToRowTopRequest: scrollToRowTopRequest
        )
        // Follow-state flips only drive SwiftUI chrome such as the jump button.
        // Reconfigure AppKit rows only when their content, layout inputs, or callbacks changed.
        if lastAppliedContentSignature == update.contentSignature {
            honorScrollRequestsIfNeeded(
                container: container,
                scrollToBottomRequest: update.scrollToBottomRequest,
                scrollToRowTopRequest: update.scrollToRowTopRequest
            )
            return
        }

        markdownPreparationGeneration += 1
        let generation = markdownPreparationGeneration
        markdownPreparationTask?.cancel()
        let preparationRequests = rowFactory.markdownPreparationRequests(for: update.items, configuration: update.rowConfiguration)
        let missingPreparationRequests = AppKitTranscriptMarkdownPreparation.missingRequests(preparationRequests)
        guard missingPreparationRequests.isEmpty || lastAppliedContentSignature == nil else {
            // Defer cold markdown rows until the shared document cache is warm; otherwise
            // AppKit's first exact height measurement would parse markdown on the main actor.
            // The initial render still installs immediately so the transcript never snapshots
            // or opens as an empty surface while preparation is in flight.
            markdownPreparationTask = Task { @MainActor [weak self, weak container] in
                await AppKitTranscriptMarkdownPreparation.prepare(missingPreparationRequests)
                guard !Task.isCancelled,
                      self?.markdownPreparationGeneration == generation,
                      let container else {
                    return
                }
                self?.applyPreparedUpdate(
                    container: container,
                    update: update
                )
            }
            return
        }

        applyPreparedUpdate(
            container: container,
            update: update
        )
    }

    private func applyPreparedUpdate(
        container: AppKitTranscriptScrollContainerView,
        update: AppKitTranscriptPreparedUpdate
    ) {
        var rowConfiguration = update.rowConfiguration
        var pendingDirtyRowIDs: Set<String> = []
        var isBuildingRows = true
        rowConfiguration.onRowHeightInvalidated = { [weak self, weak container] rowID, animatesLayoutChanges in
            // Row configure can invalidate height before the new row list is installed;
            // batch those ids so the container never lays out the previous document.
            if isBuildingRows {
                pendingDirtyRowIDs.insert(rowID)
                return
            }
            container?.rowHeightInvalidated(
                rowID: rowID,
                // Row height callbacks can arrive after SwiftUI's `isFollowing`
                // snapshot was captured. Read the coordinator's latest follow
                // state for streaming rows because follow-state-only updates do
                // not reconfigure cached row callbacks.
                preserveBottomIfFollowing: true,
                forceBottomIfPreserving: rowID == AppKitTranscriptTransientRows.streamingRowID && self?.currentIsFollowing == true,
                animatesLayoutChanges: animatesLayoutChanges
            )
        }

        let rows = rowFactory.makeRows(for: update.items, transientRows: update.transientRows, configuration: rowConfiguration)
        isBuildingRows = false
        let hasPendingRowTopScroll = shouldHonorRowTopRequest(update.scrollToRowTopRequest)
        container.configure(
            rows: rows,
            dirtyRowIDs: pendingDirtyRowIDs,
            preserveBottomIfFollowing: update.isFollowing && !hasPendingRowTopScroll
        )
        lastAppliedContentSignature = update.contentSignature

        honorScrollRequestsIfNeeded(
            container: container,
            scrollToBottomRequest: update.scrollToBottomRequest,
            scrollToRowTopRequest: update.scrollToRowTopRequest
        )
    }

    private func honorScrollRequestsIfNeeded(
        container: AppKitTranscriptScrollContainerView,
        scrollToBottomRequest: Int,
        scrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest?
    ) {
        if shouldHonorRowTopRequest(scrollToRowTopRequest),
           let scrollToRowTopRequest,
           container.scrollToRowTop(
               rowID: scrollToRowTopRequest.rowID,
               topInset: scrollToRowTopRequest.topInset
           ) {
            lastScrollToRowTopRequest = scrollToRowTopRequest
            lastScrollToBottomRequest = scrollToBottomRequest
            return
        }

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

    private func shouldHonorRowTopRequest(_ request: AppKitTranscriptRowTopScrollRequest?) -> Bool {
        guard let request else {
            return false
        }
        return lastScrollToRowTopRequest != request
    }
}

private struct AppKitTranscriptPreparedUpdate {
    let items: [ChatItem]
    let transientRows: AppKitTranscriptTransientRows
    let rowConfiguration: AppKitTranscriptRowFactory.Configuration
    let isFollowing: Bool
    let scrollToBottomRequest: Int
    let scrollToRowTopRequest: AppKitTranscriptRowTopScrollRequest?

    var contentSignature: ContentSignature {
        ContentSignature(
            items: items,
            transientRows: transientRows,
            bubbleMaxWidth: rowConfiguration.bubbleMaxWidth,
            typography: rowConfiguration.typography,
            markdownBaseURL: rowConfiguration.markdownBaseURL,
            expandedRowIDs: rowConfiguration.expandedRowIDs,
            pendingToolApproval: rowConfiguration.pendingToolApproval,
            retryableFailedMessageIDs: rowConfiguration.retryableFailedMessageIDs,
            hasUnansweredPrompt: rowConfiguration.hasUnansweredPrompt,
            actionContextID: rowConfiguration.actionContextID,
            promptBusyStates: promptBusyStates,
            approvalSelections: approvalSelections
        )
    }

    private var promptBusyStates: [String: Bool] {
        Dictionary(items.compactMap { item in
            guard case .promptBlock(_, let prompt) = item else {
                return nil
            }
            return (prompt.id, rowConfiguration.isPromptBusy(prompt))
        }, uniquingKeysWith: { _, latest in latest })
    }

    private var approvalSelections: [String: ToolApprovalSelection] {
        Dictionary(items.flatMap { item in
            switch item {
            case .toolApproval(_, let approval, _):
                return [(approval.sessionId, rowConfiguration.selectedApprovalSelection(approval))]
            case .toolApprovalBatch(_, let approvals, _):
                return approvals.map { ($0.sessionId, rowConfiguration.selectedApprovalSelection($0)) }
            case .userMessage,
                 .assistantMessage,
                 .toolGroup,
                 .standaloneTool,
                 .subAgentBlock,
                 .taskListBlock,
                 .promptBlock,
                 .centeredNote,
                 .error:
                return []
            }
        }, uniquingKeysWith: { _, latest in latest })
    }

    struct ContentSignature: Equatable {
        let items: [ChatItem]
        let transientRows: AppKitTranscriptTransientRows
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography
        let markdownBaseURL: URL?
        let expandedRowIDs: Set<String>
        let pendingToolApproval: PendingToolApproval?
        let retryableFailedMessageIDs: Set<String>
        let hasUnansweredPrompt: Bool
        let actionContextID: String
        let promptBusyStates: [String: Bool]
        let approvalSelections: [String: ToolApprovalSelection]
    }
}
