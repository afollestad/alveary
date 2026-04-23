import Foundation
import SwiftData
import SwiftUI

struct ChatView: View {
    let viewModel: ConversationViewModel
    let conversation: Conversation
    let diffViewModel: DiffViewerViewModel
    let composerCapabilities: ComposerCapabilities
    let workingDirectory: String?
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    @Bindable var appState: AppState

    @Query private var events: [ConversationEventRecord]
    @State private var lastScrollTime: Date = .distantPast
    @State private var isFollowing = true
    @State private var scrollToBottomRequest = 0

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
        if !hasVisibleChatContent, viewModel.state.isCancellingInitialSetup {
            return .progressOnly(.cancellingInitialSetup)
        }
        if !hasVisibleChatContent, viewModel.setupPhase != nil {
            return .progressOnly(.initialSetup)
        }
        if viewModel.state.isReconfiguringSession {
            return .progressOnly(.reconfiguringSession)
        }
        if let pendingToolApproval = viewModel.state.pendingToolApproval {
            return .progressOnly(.toolApproval(pendingToolApproval.request.composerStatusText))
        }
        if viewModel.turnState.isActive {
            return .busy(canStop: true)
        }
        if viewModel.state.isSendingMessage {
            return .busy(canStop: false)
        }
        return .idle
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { conversation.thread?.model ?? AppSettings.defaultModelValue },
            set: { viewModel.applyModelChange($0) }
        )
    }

    private var selectedEffortBinding: Binding<String> {
        Binding(
            get: { AppSettings.normalizedEffortLevel(conversation.thread?.effort) },
            set: { viewModel.applyEffortChange($0) }
        )
    }

    private var selectedPermissionModeBinding: Binding<String> {
        Binding(
            get: { conversation.thread?.permissionMode ?? "default" },
            set: { viewModel.applyPermissionModeChange($0) }
        )
    }

    private var selectedUseWorktreeBinding: Binding<Bool> {
        Binding(
            get: { conversation.thread?.useWorktree ?? false },
            set: { viewModel.applyWorktreePreferenceChange($0) }
        )
    }

    private var showWorktreePicker: Bool {
        guard let thread = conversation.thread,
              let project = thread.project else {
            return false
        }

        return project.isGitRepository && !thread.hasCompletedInitialSetup
    }

    private var sessionLocationLabel: String? {
        guard let thread = conversation.thread,
              let project = thread.project,
              project.isGitRepository,
              thread.hasCompletedInitialSetup else {
            return nil
        }

        return ChatInputFieldTextSupport.sessionLocationLabel(
            useWorktree: thread.useWorktree,
            worktreePath: thread.worktreePath
        )
    }

    init(
        viewModel: ConversationViewModel,
        conversation: Conversation,
        diffViewModel: DiffViewerViewModel,
        composerCapabilities: ComposerCapabilities,
        workingDirectory: String?,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        appState: AppState
    ) {
        self.viewModel = viewModel
        self.conversation = conversation
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
                    isCancellingInitialSetup: viewModel.state.isCancellingInitialSetup,
                    error: showsCenteredPreHistoryRetry ? viewModel.lastTurnError : nil,
                    onRetry: retryDraft
                )
            } else {
                ChatTranscriptView(
                    viewModel: viewModel,
                    events: events,
                    promptSubmissionIsBusy: promptSubmissionIsBusy,
                    workingDirectory: workingDirectory,
                    lastScrollTime: $lastScrollTime,
                    isFollowing: $isFollowing,
                    scrollToBottomRequest: $scrollToBottomRequest
                )
            }

            ChatComposerPanel(
                viewModel: viewModel,
                diffViewModel: diffViewModel,
                composerCapabilities: composerCapabilities,
                workingDirectory: workingDirectory,
                showsTopDivider: hasVisibleChatContent && !isFollowing,
                showsCenteredPreHistoryRetry: showsCenteredPreHistoryRetry,
                composerMode: composerMode,
                composerIsBusy: composerIsBusy,
                selectedModel: selectedModelBinding,
                selectedEffort: selectedEffortBinding,
                selectedPermissionMode: selectedPermissionModeBinding,
                selectedUseWorktree: selectedUseWorktreeBinding,
                showWorktreePicker: showWorktreePicker,
                sessionLocationLabel: sessionLocationLabel,
                loadFileCompletions: loadFileCompletions,
                loadSkillCompletions: loadSkillCompletions,
                onSubmit: sendDraft,
                onSteer: steerDraft,
                onStop: {
                    Task { await viewModel.cancel() }
                },
                appState: appState
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension ChatView {
    func retryDraft() {
        let message = viewModel.state.inputDraft
        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let outboundMessage = outboundMessage(from: message)

        requestScrollToBottom()
        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.queueOrSend(outboundMessage)
            } catch is CancellationError {
                // User-initiated cancellation — rollback already restored the draft.
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

        requestScrollToBottom()
        viewModel.state.inputDraft = ""
        Task {
            do {
                try await viewModel.queueOrSend(outboundMessage)
            } catch is CancellationError {
                // User-initiated cancellation — rollback already restored the draft.
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

        requestScrollToBottom()
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

    func requestScrollToBottom() {
        isFollowing = true
        scrollToBottomRequest += 1
    }

    func outboundMessage(from message: String) -> String {
        ChatInputFieldTextSupport.outboundMessage(from: message, workingDirectory: workingDirectory)
    }
}
