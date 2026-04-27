import Foundation
import SwiftData
import SwiftUI

struct ChatView: View {
    let viewModel: ConversationViewModel
    let conversation: Conversation
    let composerCapabilities: ComposerCapabilities
    let providerID: String
    let contextWindowCache: any ContextWindowCache
    let workingDirectory: String?
    let projectTrustPrompt: ProjectTrustPrompt?
    let isProjectTrustBlocked: Bool
    let onTrustProject: (ProjectTrustPrompt) -> Void
    let onDenyProjectTrust: (ProjectTrustPrompt) -> Void
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    @Bindable var appState: AppState

    @Query private var events: [ConversationEventRecord]
    @State private var lastScrollTime: Date = .distantPast
    @State private var isFollowing = true
    @State private var scrollToBottomRequest = 0
    @State private var displayedContentMode: ChatMainContentMode?
    @State private var cachedContextWindowSize: Int?

    private var hasVisibleChatContent: Bool {
        !events.isEmpty || !viewModel.state.grouper.items.isEmpty || viewModel.streamingText != nil
    }

    private var composerIsBusy: Bool {
        viewModel.turnState.isActive || viewModel.state.isSendingMessage
    }

    private var composerMode: ComposerMode {
        if viewModel.state.isCancellingInitialSetup {
            return .progressOnly(.cancellingInitialSetup)
        }
        if viewModel.setupPhase != nil {
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

    private var selectedModelValue: String {
        conversation.thread?.model ?? AppSettings.defaultModelValue
    }

    private var contextWindowCacheLookupID: String {
        "\(providerID):\(selectedModelValue)"
    }

    private var usageSummary: ConversationUsageSummary? {
        ConversationUsageSummary.derive(
            from: events,
            cachedContextWindowSize: cachedContextWindowSize
        )
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
        composerCapabilities: ComposerCapabilities,
        providerID: String,
        contextWindowCache: any ContextWindowCache,
        workingDirectory: String?,
        projectTrustPrompt: ProjectTrustPrompt?,
        isProjectTrustBlocked: Bool,
        onTrustProject: @escaping (ProjectTrustPrompt) -> Void,
        onDenyProjectTrust: @escaping (ProjectTrustPrompt) -> Void,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        appState: AppState
    ) {
        self.viewModel = viewModel
        self.conversation = conversation
        self.composerCapabilities = composerCapabilities
        self.providerID = providerID
        self.contextWindowCache = contextWindowCache
        self.workingDirectory = workingDirectory
        self.projectTrustPrompt = projectTrustPrompt
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.onTrustProject = onTrustProject
        self.onDenyProjectTrust = onDenyProjectTrust
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
            let contentMode = displayedContentMode ?? targetContentMode
            mainContentView(for: contentMode)
                .id(contentMode.transitionID)
                .onAppear {
                    displayedContentMode = targetContentMode
                }
                .onChange(of: targetContentMode) { _, newMode in
                    withAnimation(.easeInOut(duration: 0.25)) {
                        displayedContentMode = newMode
                    }
                }

            ChatComposerPanel(
                viewModel: viewModel,
                composerCapabilities: composerCapabilities,
                workingDirectory: workingDirectory,
                showsTopDivider: hasVisibleChatContent && !isFollowing,
                composerMode: composerMode,
                composerIsBusy: composerIsBusy,
                isProjectTrustBlocked: isProjectTrustBlocked,
                selectedModel: selectedModelBinding,
                selectedEffort: selectedEffortBinding,
                selectedPermissionMode: selectedPermissionModeBinding,
                selectedUseWorktree: selectedUseWorktreeBinding,
                showWorktreePicker: showWorktreePicker,
                sessionLocationLabel: sessionLocationLabel,
                usageSummary: usageSummary,
                loadFileCompletions: loadFileCompletions,
                loadSkillCompletions: loadSkillCompletions,
                onSubmit: sendDraft,
                onSteer: steerDraft,
                onStop: {
                    Task { await viewModel.cancel() }
                },
                focusRequestToken: $appState.pendingComposerFocusToken
            )
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: contextWindowCacheLookupID) {
            let providerID = providerID
            let selectedModel = selectedModelValue
            cachedContextWindowSize = nil
            let size = await contextWindowCache.contextWindowSize(providerId: providerID, model: selectedModel)
            guard !Task.isCancelled else {
                return
            }
            cachedContextWindowSize = size
        }
    }
}

private extension ChatView {
    var targetContentMode: ChatMainContentMode {
        if let projectTrustPrompt {
            return .projectTrust(projectTrustPrompt)
        }
        // Keep the main pane blank while the initial trust refresh is still resolving.
        if isProjectTrustBlocked, !hasVisibleChatContent {
            return .projectTrustPlaceholder
        }
        if !hasVisibleChatContent {
            return .emptyThread
        }
        return .transcript
    }

    @ViewBuilder
    func mainContentView(for mode: ChatMainContentMode) -> some View {
        switch mode {
        case .projectTrust(let projectTrustPrompt):
            ProjectTrustPromptView(
                prompt: projectTrustPrompt,
                onTrust: { onTrustProject(projectTrustPrompt) },
                onDeny: { onDenyProjectTrust(projectTrustPrompt) }
            )
            .transition(.opacity)
        case .projectTrustPlaceholder:
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
        case .emptyThread:
            EmptyThreadState(
                setupPhase: viewModel.setupPhase,
                isCancellingInitialSetup: viewModel.state.isCancellingInitialSetup
            )
            .transition(.opacity)
        case .transcript:
            ChatTranscriptView(
                viewModel: viewModel,
                events: events,
                workingDirectory: workingDirectory,
                lastScrollTime: $lastScrollTime,
                isFollowing: $isFollowing,
                scrollToBottomRequest: $scrollToBottomRequest
            )
            .transition(.opacity)
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
        let retryableMessageCount = viewModel.state.retryableFailedMessageIDs.count
        Task {
            do {
                try await viewModel.queueOrSend(outboundMessage)
            } catch is CancellationError {
                // User-initiated cancellation — rollback already restored the draft.
            } catch {
                if viewModel.state.retryableFailedMessageIDs.count == retryableMessageCount {
                    viewModel.state.inputDraft = message
                }
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

private enum ChatMainContentMode: Equatable {
    case projectTrust(ProjectTrustPrompt)
    case projectTrustPlaceholder
    case emptyThread
    case transcript

    var transitionID: String {
        switch self {
        case .projectTrust(let prompt):
            return "projectTrust-\(prompt.threadID)"
        case .projectTrustPlaceholder:
            return "projectTrustPlaceholder"
        case .emptyThread:
            return "emptyThread"
        case .transcript:
            return "transcript"
        }
    }
}
