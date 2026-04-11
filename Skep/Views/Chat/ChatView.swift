import Foundation
import SwiftData
import SwiftUI

struct ChatView: View {
    let viewModel: ConversationViewModel
    let conversation: Conversation
    let agentsManager: any AgentsManager
    let modelContext: ModelContext
    let diffViewModel: DiffViewerViewModel
    let composerCapabilities: ComposerCapabilities
    let workingDirectory: String?
    let loadFileCompletions: () async -> [String]
    let loadSkillCompletions: () async -> [Skill]
    @Bindable var appState: AppState

    @Query private var events: [ConversationEventRecord]
    @State private var lastScrollTime: Date = .distantPast
    @State private var isFollowing = true

    private var hasVisibleChatContent: Bool {
        !events.isEmpty || !viewModel.state.grouper.items.isEmpty || viewModel.streamingText != nil
    }

    private var showsCenteredPreHistoryRetry: Bool {
        !hasVisibleChatContent && viewModel.setupPhase == nil && viewModel.lastTurnError != nil
    }

    private var composerIsBusy: Bool {
        viewModel.turnState.isActive || viewModel.state.isSendingMessage
    }

    private var promptSubmissionIsBusy: Bool {
        composerIsBusy || viewModel.state.isReconfiguringSession
    }

    private var composerMode: ComposerMode {
        if !hasVisibleChatContent, viewModel.setupPhase != nil {
            return .progressOnly(.initialSetup)
        }
        if viewModel.state.isReconfiguringSession {
            return .progressOnly(.reconfiguringSession)
        }
        if viewModel.turnState.isActive {
            return .busy(canStop: true)
        }
        if viewModel.state.isSendingMessage {
            return .busy(canStop: false)
        }
        return .idle
    }

    private var canShowWriteEscalation: Bool {
        guard let suggestedMode = composerCapabilities.suggestedWriteEscalationMode,
              suggestedMode != selectedPermissionModeBinding.wrappedValue else {
            return false
        }

        return !viewModel.state.lastPermissionDeniedToolNames.isDisjoint(with: composerCapabilities.writeEscalationEligibleTools)
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { viewModel.state.selectedModel ?? "default" },
            set: { applyModelChange($0) }
        )
    }

    private var selectedEffortBinding: Binding<String> {
        Binding(
            get: { conversation.thread?.effort ?? "medium" },
            set: { applyEffortChange($0) }
        )
    }

    private var selectedPermissionModeBinding: Binding<String> {
        Binding(
            get: { conversation.thread?.permissionMode ?? "default" },
            set: { applyPermissionModeChange($0) }
        )
    }

    init(
        viewModel: ConversationViewModel,
        conversation: Conversation,
        agentsManager: any AgentsManager,
        modelContext: ModelContext,
        diffViewModel: DiffViewerViewModel,
        composerCapabilities: ComposerCapabilities,
        workingDirectory: String?,
        loadFileCompletions: @escaping () async -> [String],
        loadSkillCompletions: @escaping () async -> [Skill],
        appState: AppState
    ) {
        self.viewModel = viewModel
        self.conversation = conversation
        self.agentsManager = agentsManager
        self.modelContext = modelContext
        self.diffViewModel = diffViewModel
        self.composerCapabilities = composerCapabilities
        self.workingDirectory = workingDirectory
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.appState = appState

        let conversationID = conversation.id
        _events = Query(
            filter: #Predicate { $0.conversationId == conversationID },
            sort: \.timestamp
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !hasVisibleChatContent {
                EmptyThreadState(
                    showsRetryState: showsCenteredPreHistoryRetry,
                    setupPhase: viewModel.setupPhase,
                    error: showsCenteredPreHistoryRetry ? viewModel.lastTurnError : nil,
                    onRetry: retryDraft
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(viewModel.state.grouper.items) { item in
                                switch item {
                                case .userMessage(_, let text):
                                    UserBubble(text: text)
                                case .assistantMessage(_, let text):
                                    AssistantBubble(markdown: text)
                                case .workingBlock(_, let tools):
                                    WorkingBlock(tools: tools)
                                case .subAgentBlock(_, let agents):
                                    SubAgentBlock(agents: agents)
                                case .taskListBlock(_, let tasks):
                                    TaskListBlock(tasks: tasks)
                                case .promptBlock(_, let prompt):
                                    PromptBlock(prompt: prompt, isBusy: promptSubmissionIsBusy) { answers in
                                        do {
                                            return try await viewModel.answerPrompt(promptId: prompt.id, answers: answers)
                                        } catch {
                                            if viewModel.lastTurnError == nil {
                                                viewModel.lastTurnError = "Failed to send answer: \(error.localizedDescription)"
                                            }
                                            return nil
                                        }
                                    }
                                case .thinking(_, let text):
                                    ThinkingBlock(text: text)
                                case .error(_, let message):
                                    ErrorBanner(message: message)
                                }
                            }

                            if let streamingText = viewModel.streamingText {
                                StreamingBubble(text: streamingText)
                                    .id("streaming")
                            }

                            ForEach(viewModel.messageQueue.pending) { entry in
                                QueuedMessageBubble(
                                    text: entry.text,
                                    showsStagedContext: entry.stagedContext != nil,
                                    showsRetry: viewModel.state.inFlightQueuedMessageID == nil
                                        && viewModel.messageQueue.peekNext()?.id == entry.id
                                        && !viewModel.state.turnState.isActive,
                                    isDismissDisabled: viewModel.state.inFlightQueuedMessageID == entry.id,
                                    onRetry: {
                                        Task { try? await viewModel.retryNextQueuedMessage() }
                                    },
                                    onDismiss: {
                                        viewModel.removeQueuedMessage(id: entry.id)
                                    }
                                )
                            }

                            Color.clear
                                .frame(height: 1)
                                .id("chat-bottom")
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 20)
                    }
                    .transaction { transaction in
                        if viewModel.turnState.isActive {
                            transaction.disablesAnimations = true
                        }
                    }
                    .onScrollGeometryChange(for: Bool.self) { geometry in
                        let distanceFromBottom = geometry.contentSize.height - (geometry.contentOffset.y + geometry.containerSize.height)
                        return distanceFromBottom < 60
                    } action: { _, isNearBottom in
                        isFollowing = isNearBottom
                    }
                    .onChange(of: events.count) {
                        viewModel.rebuildChatItemsIfNeeded(from: events)
                        if isFollowing {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.messageQueue.pending.count) {
                        guard isFollowing else {
                            return
                        }
                        proxy.scrollTo("chat-bottom", anchor: .bottom)
                    }
                    .onChange(of: viewModel.streamingText) {
                        guard isFollowing else {
                            return
                        }

                        let now = Date()
                        if now.timeIntervalSince(lastScrollTime) >= 0.1 {
                            lastScrollTime = now
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onAppear {
                        viewModel.rebuildChatItemsIfNeeded(from: events)
                        if hasVisibleChatContent {
                            proxy.scrollTo("chat-bottom", anchor: .bottom)
                        }
                    }
                    .onChange(of: viewModel.turnState.isActive) { _, isActive in
                        if isActive {
                            isFollowing = true
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !isFollowing && (viewModel.turnState.isActive || viewModel.streamingText != nil) {
                            Button {
                                isFollowing = true
                                proxy.scrollTo("chat-bottom", anchor: .bottom)
                            } label: {
                                Label("Jump to bottom", systemImage: "arrow.down")
                            }
                            .buttonStyle(.borderedProminent)
                            .padding(.bottom, 12)
                        }
                    }
                }
            }

            VStack(spacing: 10) {
                if let lastTurnError = viewModel.lastTurnError,
                   !showsCenteredPreHistoryRetry {
                    InlineBanner(message: lastTurnError, severity: .error, autoDismissAfter: nil) {
                        viewModel.lastTurnError = nil
                    }
                }

                if viewModel.state.isReconfiguringSession {
                    ReconfigureStatusBanner(message: "Applying session changes...")
                }

                if let sessionContinuityNotice = viewModel.sessionContinuityNotice {
                    InlineBanner(message: sessionContinuityNotice, severity: .warning, autoDismissAfter: nil) {
                        viewModel.sessionContinuityNotice = nil
                    }
                }

                if viewModel.state.showPermissionBanner {
                    PermissionBanner(
                        canEscalate: canShowWriteEscalation,
                        isActionDisabled: composerIsBusy || viewModel.state.isReconfiguringSession,
                        escalationLabel: permissionEscalationLabel,
                        onDismiss: {
                            viewModel.state.showPermissionBanner = false
                        },
                        onEscalate: {
                            if let escalationMode = composerCapabilities.suggestedWriteEscalationMode {
                                applyPermissionModeChange(escalationMode)
                            }
                        }
                    )
                }

                if let stagedContext = viewModel.stagedContext {
                    StagedContextBanner(context: stagedContext) {
                        viewModel.stagedContext = nil
                    }
                }

                if !diffViewModel.files.isEmpty {
                    ChangedFilesStrip(
                        files: diffViewModel.files,
                        onOpenDiff: { file in
                            appState.isRightPaneVisible = true
                            guard let directory = diffViewModel.activeDirectory else {
                                return
                            }
                            Task {
                                await diffViewModel.selectFile(file, in: directory)
                            }
                        }
                    )
                }

                ChatInputField(
                    text: Bindable(viewModel.state).inputDraft,
                    mode: composerMode,
                    onSubmit: sendDraft,
                    onSteer: steerDraft,
                    onStop: {
                        Task { await viewModel.cancel() }
                    },
                    selectedModel: selectedModelBinding,
                    selectedEffort: selectedEffortBinding,
                    selectedPermissionMode: selectedPermissionModeBinding,
                    supportedPermissionModes: composerCapabilities.supportedPermissionModes,
                    supportedEffortLevels: composerCapabilities.supportedEffortLevels,
                    supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
                    workingDirectory: workingDirectory,
                    loadFileCompletions: loadFileCompletions,
                    loadSkillCompletions: loadSkillCompletions
                )
            }
            .padding(20)
            .background(.bar)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ChatView {
    var permissionEscalationLabel: String {
        switch composerCapabilities.suggestedWriteEscalationMode {
        case "acceptEdits":
            return "Switch to Auto-Edit"
        case "auto":
            return "Switch to Auto"
        case "bypassPermissions":
            return "Switch to Auto-Approve"
        case let mode?:
            return "Switch to \(mode)"
        case nil:
            return "Update permissions"
        }
    }

    func retryDraft() {
        let message = viewModel.state.inputDraft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let outboundMessage = outboundMessage(from: message)

        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.queueOrSend(outboundMessage)
            } catch {
                viewModel.state.inputDraft = message
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    func sendDraft() {
        let message = viewModel.state.inputDraft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let outboundMessage = outboundMessage(from: message)

        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.queueOrSend(outboundMessage)
            } catch {
                viewModel.state.inputDraft = message
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    func steerDraft() {
        let message = viewModel.state.inputDraft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let outboundMessage = outboundMessage(from: message)

        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.steer(outboundMessage)
            } catch {
                viewModel.state.inputDraft = message
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = "Steer failed: \(error.localizedDescription)"
                }
            }
        }
    }

    func applyModelChange(_ newValue: String) {
        let previousValue = viewModel.state.selectedModel ?? "default"
        guard previousValue != newValue else {
            return
        }

        viewModel.state.selectedModel = newValue == "default" ? nil : newValue
        viewModel.lastTurnError = nil

        Task { @MainActor in
            guard await agentsManager.isRunning(conversationId: conversation.id) else {
                return
            }

            do {
                try await viewModel.reconfigureSession()
            } catch {
                viewModel.state.selectedModel = previousValue == "default" ? nil : previousValue
                viewModel.lastTurnError = error.localizedDescription
            }
        }
    }

    func applyEffortChange(_ newValue: String) {
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.model(for: threadID) as? AgentThread else {
            return
        }

        let previousValue = dbThread.effort
        guard previousValue != newValue else {
            return
        }

        dbThread.effort = newValue
        viewModel.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.effort = previousValue
            viewModel.lastTurnError = error.localizedDescription
            return
        }

        Task { @MainActor in
            guard await agentsManager.isRunning(conversationId: conversation.id) else {
                return
            }

            do {
                try await viewModel.reconfigureSession()
            } catch {
                dbThread.effort = previousValue
                try? modelContext.save()
                viewModel.lastTurnError = error.localizedDescription
            }
        }
    }

    func applyPermissionModeChange(_ newValue: String) {
        guard let threadID = conversation.thread?.persistentModelID,
              let dbThread = modelContext.model(for: threadID) as? AgentThread else {
            return
        }

        let previousValue = dbThread.permissionMode
        guard previousValue != newValue else {
            return
        }

        let previousBannerVisibility = viewModel.state.showPermissionBanner
        let previousDeniedTools = viewModel.state.lastPermissionDeniedToolNames

        dbThread.permissionMode = newValue
        viewModel.lastTurnError = nil

        do {
            try modelContext.save()
        } catch {
            dbThread.permissionMode = previousValue
            viewModel.lastTurnError = error.localizedDescription
            return
        }

        Task { @MainActor in
            guard await agentsManager.isRunning(conversationId: conversation.id) else {
                viewModel.state.showPermissionBanner = false
                viewModel.state.lastPermissionDeniedToolNames = []
                return
            }

            do {
                try await viewModel.reconfigureSession()
            } catch {
                dbThread.permissionMode = previousValue
                try? modelContext.save()
                viewModel.state.showPermissionBanner = previousBannerVisibility
                viewModel.state.lastPermissionDeniedToolNames = previousDeniedTools
                viewModel.lastTurnError = error.localizedDescription
            }
        }
    }

    func outboundMessage(from message: String) -> String {
        guard message.contains("@") else {
            return message
        }

        let pattern = #"(^|[\s\(\[\{<"'])@([^\s\)\]\}>"']+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return message
        }

        let fullRange = NSRange(location: 0, length: (message as NSString).length)
        let matches = regex.matches(in: message, range: fullRange)
        guard !matches.isEmpty else {
            return message
        }

        let source = message as NSString
        let mutable = NSMutableString(string: message)
        for match in matches.reversed() {
            guard match.numberOfRanges >= 3 else {
                continue
            }

            let prefix = source.substring(with: match.range(at: 1))
            let path = source.substring(with: match.range(at: 2))
            let normalizedPath = normalizedMentionPath(path)
            mutable.replaceCharacters(in: match.range, with: prefix + normalizedPath)
        }

        return mutable as String
    }

    func normalizedMentionPath(_ path: String) -> String {
        CanonicalPath.normalizeMentionPath(path, relativeTo: workingDirectory)
    }
}
