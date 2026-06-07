import AppKit

@MainActor
/// Builds and caches AppKit transcript row views from `ChatItem` values.
///
/// The factory keeps row identity stable so expansion, prompt state, and nested
/// tool/sub-agent rows survive refreshes while the scroll container owns layout
/// and measurement.
final class AppKitTranscriptRowFactory {
    struct Configuration {
        var bubbleMaxWidth: CGFloat = .infinity
        // Settings-driven font changes are part of row configuration so cached
        // AppKit rows rebuild markdown and report fresh heights without being recreated.
        var typography: TranscriptTypography = TranscriptTypography()
        var markdownBaseURL: URL?
        var expandedRowIDs: Set<String> = []
        var pendingToolApproval: PendingToolApproval?
        var retryableFailedMessageIDs: Set<String> = []
        var hasUnansweredPrompt = false
        // Bumps when callbacks resolve against a different external context, such as link base paths.
        var actionContextID = ""
        var isPromptBusy: (PromptEntry) -> Bool = { _ in false }
        var suppressesApprovalControls: (ToolApprovalRequest) -> Bool = { _ in false }
        var selectedApprovalSelection: (ToolApprovalRequest) -> ToolApprovalSelection = { _ in .once }
        // Row-specific invalidation lets the AppKit container keep rows mounted
        // while remeasuring only the row whose variable-height content changed.
        // The Boolean carries animation intent: expansion rows animate, while
        // streaming rows opt out so stale AppKit frame animations cannot rewind text.
        var onRowHeightInvalidated: (String, Bool) -> Void = { _, _ in }
        var onUserInitiatedHeightChange: () -> Void = {}
        var onOpenMarkdownLink: (URL) -> Void = { _ in }
        var onRetryFailedUserMessage: (String) -> Void = { _ in }
        var onRowExpansionChanged: (String, Bool) -> Void = { _, _ in }
        var onApprove: (ToolApprovalRequest) -> Void = { _ in }
        var onApproveForSession: (ToolApprovalRequest, ToolApprovalSessionScope) -> Void = { _, _ in }
        var onDeny: (ToolApprovalRequest) -> Void = { _ in }
        var onSelectApprovalSelection: (ToolApprovalRequest, ToolApprovalSelection) -> Void = { _, _ in }
        var onSubmitPrompt: (PromptEntry, [(question: String, answer: String)]) async -> String? = { _, _ in nil }
    }

    private var cachedViewsByRowID: [String: NSView] = [:]

    func makeRows(
        for items: [ChatItem],
        transientRows: AppKitTranscriptTransientRows = .init(),
        configuration: Configuration
    ) -> [AppKitTranscriptLayoutRow] {
        let rows = items.flatMap { layoutRows(for: $0, configuration: configuration) }
            + layoutRows(for: transientRows, configuration: configuration)
        let liveRowIDs = Set(rows.map(\.id))
        cachedViewsByRowID = cachedViewsByRowID.filter { rowID, _ in liveRowIDs.contains(rowID) }
        return rows
    }

    // `ChatItem` is the transcript sum type; keeping this dispatch here makes
    // row coverage exhaustive while the row-specific builders stay small.
    // swiftlint:disable:next cyclomatic_complexity
    private func layoutRows(for item: ChatItem, configuration: Configuration) -> [AppKitTranscriptLayoutRow] {
        switch item {
        case .userMessage(let id, let text):
            return [textBubbleRow(id: id, role: .user, markdown: text, configuration: configuration)]
        case .assistantMessage(let id, let text):
            return [textBubbleRow(id: id, role: .assistant, markdown: text, configuration: configuration)]
        case .toolGroup(let id, let tools):
            return [toolGroupRow(id: id, tools: tools, configuration: configuration)]
        case .standaloneTool(let id, let tool):
            return standaloneToolRows(id: id, tool: tool, configuration: configuration)
        case .subAgentBlock(let id, let agents):
            return [subAgentRow(id: id, agents: agents, configuration: configuration)]
        case .taskListBlock(let id, let tasks):
            return [taskListRow(id: id, tasks: tasks, configuration: configuration)]
        case .promptBlock(let id, let prompt):
            return [promptRow(id: id, prompt: prompt, configuration: configuration)]
        case .toolApproval(let id, let approval, let status):
            return approvalRows(id: id, approvals: [approval], persistedStatus: status, configuration: configuration)
        case .toolApprovalBatch(let id, let approvals, let status):
            return approvalRows(id: id, approvals: approvals, persistedStatus: status, configuration: configuration)
        case .centeredNote(let id, let kind):
            return [centeredNoteRow(id: id, kind: kind, configuration: configuration)]
        case .error(let id, let message):
            return [errorRow(id: id, message: message, configuration: configuration)]
        }
    }

    private func layoutRows(
        for transientRows: AppKitTranscriptTransientRows,
        configuration: Configuration
    ) -> [AppKitTranscriptLayoutRow] {
        if let streamingText = transientRows.streamingText {
            return [streamingBubbleRow(text: streamingText, configuration: configuration)]
        }

        if transientRows.isTurnActive || transientRows.isAwaitingExitPlanModeFollowUp {
            return [thinkingIndicatorRow(transientRows: transientRows, configuration: configuration)]
        }

        if transientRows.showsInterruptedNote {
            return [centeredNoteRow(id: AppKitTranscriptTransientRows.interruptedRowID, kind: .interrupted, configuration: configuration)]
        }

        return []
    }

    private func streamingBubbleRow(
        text: String,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: AppKitTranscriptTransientRows.streamingRowID, as: AppKitTranscriptStreamingBubbleView.self)
        view.onHeightInvalidated = heightInvalidationHandler(
            for: AppKitTranscriptTransientRows.streamingRowID,
            animatesLayoutChanges: false,
            configuration: configuration
        )
        view.configure(
            .init(
                text: text,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        return .init(id: AppKitTranscriptTransientRows.streamingRowID, view: view)
    }

    private func thinkingIndicatorRow(
        transientRows: AppKitTranscriptTransientRows,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: AppKitTranscriptTransientRows.thinkingRowID, as: AppKitTranscriptThinkingIndicatorView.self)
        view.configure(
            .init(
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography,
                isAnimated: transientRows.isThinkingAnimated
            )
        )
        return .init(id: AppKitTranscriptTransientRows.thinkingRowID, view: view)
    }

    private func toolGroupRow(
        id: String,
        tools: [ToolEntry],
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptToolGroupView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onUserInitiatedHeightChange = configuration.onUserInitiatedHeightChange
        view.onOpenMarkdownLink = configuration.onOpenMarkdownLink
        view.onExpansionChanged = { expanded in
            configuration.onRowExpansionChanged(id, expanded)
        }
        view.configure(
            .init(
                tools: tools,
                initiallyExpanded: configuration.expandedRowIDs.contains(id),
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }

    private func standaloneToolRows(
        id: String,
        tool: ToolEntry,
        configuration: Configuration
    ) -> [AppKitTranscriptLayoutRow] {
        if let previewRow = exitPlanModeFollowUpPreviewRow(id: id, tool: tool, configuration: configuration) {
            return [previewRow]
        }
        return [standaloneToolRow(id: id, tool: tool, configuration: configuration)]
    }

    private func standaloneToolRow(
        id: String,
        tool: ToolEntry,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptInlineToolRowView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onUserInitiatedHeightChange = configuration.onUserInitiatedHeightChange
        view.onOpenMarkdownLink = configuration.onOpenMarkdownLink
        view.onExpansionChanged = { expanded in
            configuration.onRowExpansionChanged(id, expanded)
        }
        view.configure(
            .init(
                tool: tool,
                initiallyExpanded: configuration.expandedRowIDs.contains(id),
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }

    private func exitPlanModeFollowUpPreviewRow(
        id: String,
        tool: ToolEntry,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow? {
        guard tool.previewOverride?.origin == .exitPlanModeFollowUp,
              let snapshot = MinimalToolContent.snapshot(for: tool),
              snapshot.language == "markdown",
              let content = snapshot.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return textBubbleRow(
            id: "\(id)-plan-preview",
            role: .assistant,
            markdown: content,
            markdownBaseURL: snapshot.baseURL,
            configuration: configuration
        )
    }

    private func subAgentRow(
        id: String,
        agents: [SubAgentEntry],
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptSubAgentBlockView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onUserInitiatedHeightChange = configuration.onUserInitiatedHeightChange
        view.onOpenMarkdownLink = configuration.onOpenMarkdownLink
        view.onExpansionChanged = { expanded in
            configuration.onRowExpansionChanged(id, expanded)
        }
        view.configure(
            .init(
                agents: agents,
                initiallyExpanded: configuration.expandedRowIDs.contains(id),
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }

    private func taskListRow(
        id: String,
        tasks: [TaskEntry],
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptTaskListBlockView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.configure(
            .init(
                tasks: tasks,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }

    private func promptRow(
        id: String,
        prompt: PromptEntry,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptPromptBlockView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onSubmit = { answers in
            await configuration.onSubmitPrompt(prompt, answers)
        }
        view.configure(
            .init(
                prompt: prompt,
                isBusy: configuration.isPromptBusy(prompt),
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }

    private func centeredNoteRow(
        id: String,
        kind: CenteredTranscriptNoteKind,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptCenteredNoteView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.configure(.init(kind: kind, typography: configuration.typography))
        return .init(id: id, view: view)
    }

    private func errorRow(
        id: String,
        message: String,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptErrorBannerView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.configure(
            .init(
                message: message,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        return .init(id: id, view: view)
    }

    private func textBubbleRow(
        id: String,
        role: AppKitTranscriptTextBubbleRowView.Role,
        markdown: String,
        markdownBaseURL: URL? = nil,
        configuration: Configuration
    ) -> AppKitTranscriptLayoutRow {
        let view = cachedView(for: id, as: AppKitTranscriptTextBubbleRowView.self)
        view.hydratesMarkdownImmediately = false
        view.onHeightInvalidated = heightInvalidationHandler(for: id, configuration: configuration)
        view.onUserInitiatedHeightChange = configuration.onUserInitiatedHeightChange
        view.onOpenMarkdownLink = configuration.onOpenMarkdownLink
        view.onExpansionChanged = { expanded in
            configuration.onRowExpansionChanged(id, expanded)
        }
        view.onRetry = role == .user ? {
            configuration.onRetryFailedUserMessage(id)
        } : nil
        view.configure(
            .init(
                id: id,
                role: role,
                markdown: markdown,
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography.appKitMarkdownTypography,
                markdownBaseURL: markdownBaseURL ?? configuration.markdownBaseURL,
                showsRetry: role == .user && configuration.retryableFailedMessageIDs.contains(id),
                initiallyExpanded: configuration.expandedRowIDs.contains(id)
            )
        )
        return .init(id: id, view: view)
    }

    private func approvalRows(
        id: String,
        approvals: [ToolApprovalRequest],
        persistedStatus: ToolApprovalStatus?,
        configuration: Configuration
    ) -> [AppKitTranscriptLayoutRow] {
        guard let fallbackApproval = approvals.last else {
            return []
        }
        let approval = actionableApproval(in: approvals, pendingToolApproval: configuration.pendingToolApproval) ?? fallbackApproval
        var rows: [AppKitTranscriptLayoutRow] = []

        if let planMarkdown = approvalPlanMarkdown(for: approvals, actionableApproval: approval) {
            rows.append(
                textBubbleRow(
                    id: "\(id)-plan",
                    role: .assistant,
                    markdown: planMarkdown,
                    configuration: configuration
                )
            )
        }

        guard !configuration.suppressesApprovalControls(approval) else {
            return rows
        }

        let approvalRowID = "\(id)-approval"
        let view = cachedView(for: approvalRowID, as: AppKitTranscriptToolApprovalBlockView.self)
        view.onHeightInvalidated = heightInvalidationHandler(for: approvalRowID, configuration: configuration)
        view.onApprove = { configuration.onApprove(approval) }
        view.onApproveForSession = { scope in configuration.onApproveForSession(approval, scope) }
        view.onDeny = { configuration.onDeny(approval) }
        view.onSelectApprovalSelection = { selection in
            configuration.onSelectApprovalSelection(approval, selection)
        }
        view.configure(
            .init(
                approval: approval,
                approvals: approvals,
                status: approvalStatus(for: approvals, persistedStatus: persistedStatus, pendingToolApproval: configuration.pendingToolApproval),
                isBlocked: configuration.hasUnansweredPrompt,
                selectedApprovalSelection: configuration.selectedApprovalSelection(approval),
                bubbleMaxWidth: configuration.bubbleMaxWidth,
                typography: configuration.typography
            )
        )
        rows.append(.init(id: approvalRowID, view: view))
        return rows
    }

    private func approvalStatus(
        for approvals: [ToolApprovalRequest],
        persistedStatus: ToolApprovalStatus?,
        pendingToolApproval: PendingToolApproval?
    ) -> ToolApprovalStatus? {
        guard let pendingToolApproval,
              approvals.contains(where: {
                  pendingToolApproval.request.sessionId == $0.sessionId &&
                      pendingToolApproval.request.toolUseId == $0.toolUseId
              })
        else {
            return persistedStatus
        }
        return pendingToolApproval.status
    }

    func actionableApproval(
        in approvals: [ToolApprovalRequest],
        pendingToolApproval: PendingToolApproval?
    ) -> ToolApprovalRequest? {
        guard let pendingToolApproval else {
            return nil
        }
        return approvals.first {
            pendingToolApproval.request.sessionId == $0.sessionId &&
                pendingToolApproval.request.toolUseId == $0.toolUseId
        }
    }

    func approvalPlanMarkdown(
        for approvals: [ToolApprovalRequest],
        actionableApproval: ToolApprovalRequest
    ) -> String? {
        guard approvals.count == 1 else {
            return nil
        }
        return approvals.first?.planMarkdown ?? actionableApproval.planMarkdown
    }

    private func cachedView<View: NSView>(for rowID: String, as type: View.Type) -> View {
        if let existing = cachedViewsByRowID[rowID] as? View {
            return existing
        }
        let view = View(frame: .zero)
        cachedViewsByRowID[rowID] = view
        return view
    }

    private func heightInvalidationHandler(
        for rowID: String,
        animatesLayoutChanges: Bool = true,
        configuration: Configuration
    ) -> () -> Void {
        {
            configuration.onRowHeightInvalidated(rowID, animatesLayoutChanges)
        }
    }
}
