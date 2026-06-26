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
        return items.interruptedActivityTerminalized
    }

    var appKitTransientRows: AppKitTranscriptTransientRows {
        let isHiddenCommitMessageGeneration = viewModel.state.isGeneratingCommitMessage
        let suppressesTransientText = viewModel.state.isHandingOffSession || isHiddenCommitMessageGeneration
        let visibleStreamingText = suppressesTransientText
            ? nil
            : viewModel.streamingText
        let visibleThoughtText = suppressesTransientText
            ? nil
            : viewModel.thoughtText
        let visibleCompletedThoughtText = suppressesTransientText
            ? nil
            : viewModel.completedThoughtText
        return AppKitTranscriptTransientRows(
            isTurnActive: viewModel.turnState.isActive &&
                visibleStreamingText == nil &&
                visibleThoughtText == nil &&
                visibleCompletedThoughtText == nil &&
                !isHiddenCommitMessageGeneration,
            isAwaitingExitPlanModeFollowUp: viewModel.state.isAwaitingExitPlanModeFollowUp &&
                visibleStreamingText == nil &&
                visibleThoughtText == nil &&
                visibleCompletedThoughtText == nil,
            streamingText: visibleStreamingText,
            thoughtText: visibleThoughtText,
            thoughtSequence: viewModel.thoughtSequence,
            completedThoughtText: visibleCompletedThoughtText,
            completedThoughtSequence: viewModel.completedThoughtSequence,
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
        configuration.imageAttachmentsByMessageID = appKitImageAttachmentsByMessageID
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

    var appKitImageAttachmentsByMessageID: [String: [LocalImageAttachment]] {
        Self.imageAttachmentsByMessageID(
            events: events,
            runtimeImageAttachments: viewModel.state.transcriptImageAttachments,
            runtimeAppShots: viewModel.state.transcriptAppShots
        )
    }

    static func imageAttachmentsByMessageID(
        events: [ConversationEventRecord],
        runtimeImageAttachments: [String: [LocalImageAttachment]],
        runtimeAppShots: [String: [AppShotAttachment]]
    ) -> [String: [LocalImageAttachment]] {
        var attachmentsByID: [String: [LocalImageAttachment]] = [:]
        for event in events where event.type == "message" {
            appendImageAttachments(event.persistedImageAttachments, to: event.id, in: &attachmentsByID)
        }
        for (messageID, attachments) in runtimeImageAttachments {
            appendImageAttachments(attachments, to: messageID, in: &attachmentsByID)
        }
        for (messageID, appShots) in runtimeAppShots {
            appendImageAttachments(appShots.map(\.screenshot), to: messageID, in: &attachmentsByID)
        }
        return attachmentsByID
    }

    static func appendImageAttachments(
        _ newAttachments: [LocalImageAttachment],
        to messageID: String,
        in attachmentsByID: inout [String: [LocalImageAttachment]]
    ) {
        guard !newAttachments.isEmpty else {
            return
        }
        var attachments = attachmentsByID[messageID] ?? []
        var seenAttachmentIDs = Set(attachments.map(\.id))
        for attachment in newAttachments where seenAttachmentIDs.insert(attachment.id).inserted {
            attachments.append(attachment)
        }
        attachmentsByID[messageID] = attachments
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
