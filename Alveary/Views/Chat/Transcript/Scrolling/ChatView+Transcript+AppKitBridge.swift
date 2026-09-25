@preconcurrency import AppKit
import BlockInputKit
import Foundation
import SwiftUI

extension ChatTranscriptView {
    func appKitTranscriptSurface() -> some View {
        let presentation = appKitTranscriptPresentationCache.presentation(for: appKitTranscriptItems)
        return AppKitTranscriptScrollViewRepresentable(
            items: presentation.items,
            presentation: presentation,
            transientRows: appKitTransientRows,
            rowConfiguration: appKitRowConfiguration(presentation: presentation),
            isFollowing: isFollowing,
            scrollToBottomRequest: scrollToBottomRequest + appKitScrollToBottomRequest,
            scrollToRowTopRequest: nil,
            onLoadingStateChanged: handleTranscriptLoadingStateChange,
            onScrollMetricsChanged: { newMetrics in
                let oldMetrics = latestMetrics ?? newMetrics
                handleScrollMetricsChange(oldMetrics: oldMetrics, newMetrics: newMetrics)
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { newValue in
            // A transcript reports `0` until its host has a real frame, and writing that back would
            // overwrite the width `init` seeded — re-deriving `bubbleMaxWidth` as `.infinity` and
            // re-dirtying every row for one discarded pass. Only a real layout may move this.
            guard newValue > 0 else {
                return
            }
            transcriptContentWidth = newValue
            // Seeds the next transcript's first measurement pass; `TranscriptContentWidthCache`
            // owns why that pass is otherwise thrown away.
            TranscriptContentWidthCache.store(newValue)
        }
    }

    /// Memoized per render input; the key reads every observable the projection depends on.
    var appKitTranscriptItems: [ChatItem] {
        let reviewTeamRun = pullRequestReviewTeamCoordinator?.runs[viewModel.conversationID]
        let grouper = viewModel.state.grouper
        let key = AppKitTranscriptPresentationCache.TranscriptItemsKey(
            grouper: ObjectIdentifier(grouper),
            itemsRevision: grouper.itemsRevision,
            terminalizesInterruptedActivity: terminalizesInterruptedActivity,
            reviewTeamRun: reviewTeamRun,
            conversationID: viewModel.conversationID
        )
        return appKitTranscriptPresentationCache.transcriptItems(for: key) {
            appKitTranscriptItems(reviewTeamRun: reviewTeamRun)
        }
    }

    /// A failed save leaves the durable event unchanged; render the coordinator's state without altering that event.
    func appKitTranscriptItems(reviewTeamRun: ReviewTeamRun?) -> [ChatItem] {
        let items = viewModel.state.grouper.items.visibleTranscriptItems
        let visibleItems = terminalizesInterruptedActivity ? items.interruptedActivityTerminalized : items
        return visibleItems.map { item in
            guard let run = reviewTeamRun,
                  run.conversationID == viewModel.conversationID,
                  case .hostToolWidget(let id, let entry) = item,
                  case .collectiveReviewRun(let persisted) = entry.content,
                  persisted.conversationID == run.conversationID,
                  persisted.id == run.id else { return item }
            return ChatItem.collectiveReviewRun(id: id, run: run)
        }
    }

    private var terminalizesInterruptedActivity: Bool {
        viewModel.state.shouldShowInterruptedCue && !viewModel.turnState.isActive
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
            isTurnActive: (viewModel.turnState.isActive || isReviewTeamWorking) &&
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
                !isReviewTeamWorking &&
                shouldShowTransientInterruptedNote
        )
    }

    func appKitRowConfiguration(presentation: AppKitTranscriptPresentation) -> AppKitTranscriptRowFactory.Configuration {
        let migratedExpandedRowIDs = presentation.migratedExpandedRowIDs(expandedTranscriptRows)
        let validExpandedRowIDs = migratedExpandedRowIDs.intersection(presentation.expandableRowIDs)
        if validExpandedRowIDs != expandedTranscriptRows {
            Task { @MainActor in
                expandedTranscriptRows = validExpandedRowIDs
            }
        }

        let attachments = appKitTranscriptAttachments
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.bubbleMaxWidth = adaptiveTranscriptBubbleMaxWidth(for: transcriptContentWidth)
        configuration.typography = transcriptTypography
        configuration.markdownBaseURL = appKitMarkdownBaseURL
        configuration.expandedRowIDs = validExpandedRowIDs
        configuration.pendingToolApproval = viewModel.state.pendingToolApproval
        configuration.isRestoringToolApproval = viewModel.state.isRestoringToolApproval
        configuration.retryableFailedMessageIDs = viewModel.state.retryableFailedMessageIDs
        configuration.transcriptImageAttachmentsByMessageID = attachments.imagesByMessageID
        configuration.transcriptFileAttachmentsByMessageID = attachments.filesByMessageID
        configuration.hasUnansweredPrompt = viewModel.hasUnansweredPrompt
        configuration.actionContextID = workingDirectory ?? ""
        configuration.suppressesApprovalControls = { $0.toolName == "ExitPlanMode" }
        configuration.onUserInitiatedHeightChange = {
            cancelPendingScrollForUserLocalHeightChange()
        }
        configuration.onOpenMarkdownLink = openAppKitMarkdownLink(_:)
        configuration.onOpenMarkdownImage = openAppKitMarkdownImage(_:baseURL:)
        configuration.onOpenImageAttachment = openAppKitImageAttachment(_:)
        configuration.onOpenFileAttachment = openAppKitFileAttachment(_:)
        configuration.onOpenToolImage = openAppKitToolImage(_:)
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
        configureAppKitPullRequestLinkPrompts(&configuration)
        configureAppKitPullRequestWidgets(&configuration)
        configureAppKitThreadWidgets(&configuration)
        configureAppKitScheduledProposals(&configuration)
        configureAppKitReviewProposals(&configuration)
        return configuration
    }

    func configureAppKitPullRequestLinkPrompts(_ configuration: inout AppKitTranscriptRowFactory.Configuration) {
        configuration.pullRequestLinkPromptsByMessageID = viewModel.pendingPullRequestLinkPromptsByMessageID()
        configuration.selectedPullRequestPromptSelection = { promptID in
            appKitPullRequestPromptSelections[promptID] ?? .init()
        }
        configuration.onAcceptPullRequestLinkPrompt = { prompt, always in
            viewModel.acceptPullRequestLinkPrompt(prompt, always: always)
        }
        configuration.onDeclinePullRequestLinkPrompt = { prompt, never in
            appKitPullRequestPromptSelections[prompt.id] = nil
            viewModel.declinePullRequestLinkPrompt(prompt, never: never)
        }
        configuration.onSelectPullRequestPromptSelection = { promptID, selection in
            appKitPullRequestPromptSelections[promptID] = selection
        }
    }

    private var appKitTranscriptAttachments: AppKitTranscriptAttachments {
        appKitTranscriptAttachmentCache.attachments(
            events: events,
            runtimeImageAttachments: viewModel.state.transcriptImageAttachments,
            runtimeAppShots: viewModel.state.transcriptAppShots,
            runtimeFileAttachments: viewModel.state.transcriptFileAttachments
        )
    }

    static func transcriptImageAttachmentsByMessageID(
        events: [ConversationEventRecord],
        runtimeImageAttachments: [String: [LocalImageAttachment]],
        runtimeAppShots: [String: [AppShotAttachment]]
    ) -> [String: [TranscriptImageAttachment]] {
        AppKitTranscriptAttachmentCache().attachments(
            events: events,
            runtimeImageAttachments: runtimeImageAttachments,
            runtimeAppShots: runtimeAppShots,
            runtimeFileAttachments: [:]
        ).imagesByMessageID
    }

    static func transcriptFileAttachmentsByMessageID(
        events: [ConversationEventRecord],
        runtimeFileAttachments: [String: [LocalFileAttachment]]
    ) -> [String: [LocalFileAttachment]] {
        AppKitTranscriptAttachmentCache().attachments(
            events: events,
            runtimeImageAttachments: [:],
            runtimeAppShots: [:],
            runtimeFileAttachments: runtimeFileAttachments
        ).filesByMessageID
    }

    static func appendTranscriptFileAttachments(
        _ newAttachments: [LocalFileAttachment],
        to messageID: String,
        in attachmentsByID: inout [String: [LocalFileAttachment]]
    ) {
        guard !newAttachments.isEmpty else {
            return
        }
        var attachments = attachmentsByID[messageID] ?? []
        var attachmentIndicesByID: [String: Int] = [:]
        for (index, attachment) in attachments.enumerated() where attachmentIndicesByID[attachment.id] == nil {
            attachmentIndicesByID[attachment.id] = index
        }
        for attachment in newAttachments {
            if let existingIndex = attachmentIndicesByID[attachment.id] {
                attachments[existingIndex] = attachment
                continue
            }
            attachmentIndicesByID[attachment.id] = attachments.count
            attachments.append(attachment)
        }
        attachmentsByID[messageID] = attachments
    }

    static func appendTranscriptImageAttachments(
        _ newAttachments: [TranscriptImageAttachment],
        to messageID: String,
        in attachmentsByID: inout [String: [TranscriptImageAttachment]]
    ) {
        guard !newAttachments.isEmpty else {
            return
        }
        var attachments = attachmentsByID[messageID] ?? []
        var attachmentIndicesByID: [String: Int] = [:]
        for (index, attachment) in attachments.enumerated() where attachmentIndicesByID[attachment.image.id] == nil {
            attachmentIndicesByID[attachment.image.id] = index
        }
        for attachment in newAttachments {
            if let existingIndex = attachmentIndicesByID[attachment.image.id] {
                attachments[existingIndex] = mergedTranscriptImageAttachment(
                    existing: attachments[existingIndex],
                    incoming: attachment
                )
                continue
            }
            attachmentIndicesByID[attachment.image.id] = attachments.count
            attachments.append(attachment)
        }
        attachmentsByID[messageID] = attachments
    }

    private static func mergedTranscriptImageAttachment(
        existing: TranscriptImageAttachment,
        incoming: TranscriptImageAttachment
    ) -> TranscriptImageAttachment {
        guard let incomingAppShot = incoming.appShot else {
            return existing
        }
        guard let existingAppShot = existing.appShot else {
            return incoming
        }
        if existingAppShot.nonEmptyAXTreeText == nil,
           incomingAppShot.nonEmptyAXTreeText != nil {
            return incoming
        }
        if incomingAppShot.nonEmptyAXTreeText == nil,
           existingAppShot.nonEmptyAXTreeText != nil {
            return existing
        }
        return incoming
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
        cachedAppKitApprovalRequests.loadID
    }

    var appKitApprovalRequests: [ToolApprovalRequest] {
        cachedAppKitApprovalRequests.requests
    }

    private var cachedAppKitApprovalRequests: AppKitTranscriptPresentationCache.ApprovalRequests {
        let grouper = viewModel.state.grouper
        return appKitTranscriptPresentationCache.approvalRequests(grouper: grouper) {
            var seenSessionIDs: Set<String> = []
            return grouper.items.visibleTranscriptItems
                .flatMap(\.appKitApprovalRequests)
                .filter { seenSessionIDs.insert($0.sessionId).inserted }
        }
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
        if let request = AppImagePreviewRequest.supportedURL(resolved) {
            appState.presentImagePreview(request)
            return
        }
        NSWorkspace.shared.open(resolved)
    }

    func openAppKitMarkdownImage(_ image: BlockInputImage, baseURL: URL?) {
        appState.presentImagePreview(.markdownImage(image, baseURL: baseURL))
    }

    func openAppKitImageAttachment(_ attachment: TranscriptImageAttachment) {
        appState.presentImagePreview(.transcriptImageAttachment(attachment))
    }

    func openAppKitFileAttachment(_ attachment: LocalFileAttachment) {
        NSWorkspace.shared.open(attachment.fileURL)
    }

    func openAppKitToolImage(_ tool: ToolEntry) {
        guard let request = AppImagePreviewRequest.toolImageOutput(tool: tool, baseURL: appKitMarkdownBaseURL) else {
            return
        }
        appState.presentImagePreview(request)
    }

    var appKitMarkdownBaseURL: URL? {
        workingDirectory.map { URL(fileURLWithPath: $0, isDirectory: true) }
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
             .hostToolWidget,
             .promptBlock,
             .transcriptNote,
             .error:
            return []
        }
    }
}
