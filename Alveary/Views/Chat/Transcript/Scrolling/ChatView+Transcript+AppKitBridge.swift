import Foundation
import SwiftUI

extension ChatTranscriptView {
    func appKitTranscriptSurface() -> some View {
        AppKitTranscriptScrollViewRepresentable(
            items: appKitTranscriptItems,
            transientRows: appKitTransientRows,
            rowConfiguration: appKitRowConfiguration(),
            isFollowing: isFollowing,
            scrollToBottomRequest: scrollToBottomRequest + appKitScrollToBottomRequest,
            scrollToRowTopRequest: nil,
            onScrollMetricsChanged: { newMetrics in
                let oldMetrics = latestMetrics ?? newMetrics
                handleScrollMetricsChange(oldMetrics: oldMetrics, newMetrics: newMetrics)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newValue in
            transcriptContentWidth = newValue
        }
    }

    var appKitTranscriptItems: [ChatItem] {
        let items = viewModel.state.grouper.items.visibleTranscriptItems
        guard viewModel.state.shouldShowInterruptedCue,
              !viewModel.turnState.isActive else {
            return items
        }
        return items.interruptedToolsTerminalized
    }

    var appKitTransientRows: AppKitTranscriptTransientRows {
        let visibleStreamingText = viewModel.state.isHandingOffSession ? nil : viewModel.streamingText
        return AppKitTranscriptTransientRows(
            isTurnActive: viewModel.turnState.isActive && visibleStreamingText == nil,
            isAwaitingExitPlanModeFollowUp: viewModel.state.isAwaitingExitPlanModeFollowUp && visibleStreamingText == nil,
            streamingText: visibleStreamingText,
            showsInterruptedNote: viewModel.state.shouldShowInterruptedCue &&
                !viewModel.turnState.isActive &&
                shouldShowTransientInterruptedNote
        )
    }

    func appKitRowConfiguration() -> AppKitTranscriptRowFactory.Configuration {
        let expandableRowIDs = AppKitTranscriptActivityGrouping.expandableRowIDs(for: appKitTranscriptItems)
        let migratedExpandedRowIDs = AppKitTranscriptActivityGrouping.migratedExpandedRowIDs(
            expandedTranscriptRows,
            for: appKitTranscriptItems
        )
        let validExpandedRowIDs = migratedExpandedRowIDs.intersection(expandableRowIDs)
        if validExpandedRowIDs != expandedTranscriptRows {
            Task { @MainActor in
                expandedTranscriptRows = validExpandedRowIDs
            }
        }

        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = adaptiveTranscriptBubbleMaxWidth(for: transcriptContentWidth)
        configuration.typography = transcriptTypography
        configuration.markdownBaseURL = workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
        configuration.expandedRowIDs = validExpandedRowIDs
        configuration.pendingToolApproval = viewModel.state.pendingToolApproval
        configuration.retryableFailedMessageIDs = viewModel.state.retryableFailedMessageIDs
        configuration.hasUnansweredPrompt = viewModel.hasUnansweredPrompt
        configuration.actionContextID = workingDirectory ?? ""
        configuration.suppressesApprovalControls = { $0.toolName == "ExitPlanMode" }
        configuration.onUserInitiatedHeightChange = {
            cancelPendingScrollForUserLocalHeightChange()
        }
        configuration.onOpenMarkdownLink = openAppKitMarkdownLink(_:)
        configuration.onRetryFailedUserMessage = { id in
            retryAction(for: id, isRetryable: true)?()
        }
        configuration.onRowExpansionChanged = { rowID, isExpanded in
            if isExpanded {
                expandedTranscriptRows.insert(rowID)
            } else {
                expandedTranscriptRows.remove(rowID)
            }
        }
        configureAppKitApprovalRows(&configuration)
        return configuration
    }

    func configureAppKitApprovalRows(_ configuration: inout AppKitTranscriptRowFactory.Configuration) {
        configuration.selectedApprovalSelection = { approval in
            appKitToolApprovalSelectionsBySessionID[approval.sessionId]
                ?? approval.recommendedApprovalSelection
                ?? .once
        }
        configuration.onApprove = { approval in
            resolveAppKitToolApproval(approval, approve: true)
        }
        configuration.onApproveForSession = { approval, scope in
            resolveAppKitToolApprovalForSession(approval, scope: scope)
        }
        configuration.onDeny = { approval in
            resolveAppKitToolApproval(approval, approve: false)
        }
        configuration.onSelectApprovalSelection = { approval, selection in
            appKitToolApprovalSelectionsBySessionID[approval.sessionId] = selection
            viewModel.recordToolApprovalSelection(selection, for: approval)
        }
    }

    var appKitApprovalSelectionLoadID: String {
        appKitApprovalRequests.map(\.sessionId).joined(separator: "|")
    }

    var appKitApprovalRequests: [ToolApprovalRequest] {
        var seenSessionIDs: Set<String> = []
        return viewModel.state.grouper.items.visibleTranscriptItems
            .flatMap(\.appKitApprovalRequests)
            .filter { seenSessionIDs.insert($0.sessionId).inserted }
    }

    func loadAppKitApprovalSelectionsIfNeeded() async {
        let approvals = appKitApprovalRequests
        let liveSessionIDs = Set(approvals.map(\.sessionId))
        appKitToolApprovalSelectionsBySessionID = appKitToolApprovalSelectionsBySessionID.filter { liveSessionIDs.contains($0.key) }

        for approval in approvals where appKitToolApprovalSelectionsBySessionID[approval.sessionId] == nil {
            guard let selection = await viewModel.toolApprovalSelection(for: approval) else {
                continue
            }
            guard !Task.isCancelled else {
                return
            }
            // Do not overwrite a selection the user changed while the async load was in flight.
            if liveSessionIDs.contains(approval.sessionId),
               appKitToolApprovalSelectionsBySessionID[approval.sessionId] == nil {
                appKitToolApprovalSelectionsBySessionID[approval.sessionId] = selection
            }
        }
    }

    func openAppKitMarkdownLink(_ url: URL) {
        let resolved = Self.resolveMarkdownLinkURL(url, workingDirectory: workingDirectory)
        NSWorkspace.shared.open(resolved)
    }

    func resolveAppKitToolApproval(_ approval: ToolApprovalRequest, approve: Bool) {
        Task {
            do {
                if approve {
                    try await viewModel.approveToolUse(approval)
                } else {
                    try await viewModel.denyToolUse(approval)
                }
            } catch {
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    func resolveAppKitToolApprovalForSession(_ approval: ToolApprovalRequest, scope: ToolApprovalSessionScope) {
        Task {
            do {
                try await viewModel.approveToolUseForSession(approval, scope: scope)
            } catch {
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }
}

private extension ChatItem {
    var appKitApprovalRequests: [ToolApprovalRequest] {
        switch self {
        case .toolApproval(_, let approval, _):
            return [approval]
        case .toolApprovalBatch(_, let approvals, _):
            return approvals
        case .userMessage,
             .assistantMessage,
             .toolGroup,
             .standaloneTool,
             .subAgentBlock,
             .taskListBlock,
             .promptBlock,
             .transcriptNote,
             .error:
            return []
        }
    }
}
