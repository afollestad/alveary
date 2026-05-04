import Foundation
import SwiftData
import SwiftUI

struct ChatView: View {
    let viewModel: ConversationViewModel
    let conversation: Conversation
    let composerCapabilities: ComposerCapabilities
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let providerID: String
    let contextWindowCache: any ContextWindowCache
    let workingDirectory: String?
    let projectTrustPrompt: ProjectTrustPrompt?
    let isProjectTrustBlocked: Bool
    let onTrustProject: (ProjectTrustPrompt) -> Void
    let onDenyProjectTrust: (ProjectTrustPrompt) -> Void
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let transcriptTypography: TranscriptTypography
    @Bindable var appState: AppState

    @Query private var events: [ConversationEventRecord]
    @State private var lastScrollTime: Date = .distantPast
    @State private var isFollowing = true
    @State private var scrollToBottomRequest = 0
    @State private var displayedContentMode: ChatContentMode?
    @State private var cachedContextWindowSize: Int?

    private var hasVisibleChatContent: Bool {
        ChatPresentation.hasVisibleChatContent(
            hasEvents: !events.isEmpty,
            hasGroupedItems: !viewModel.state.grouper.items.isEmpty,
            hasStreamingText: viewModel.streamingText != nil
        )
    }

    private var composerIsBusy: Bool {
        viewModel.turnState.isActive || viewModel.state.isSendingMessage
    }

    private var composerMode: ComposerMode {
        ChatPresentation.composerMode(for: ChatComposerModeState(
            isCancellingInitialSetup: viewModel.state.isCancellingInitialSetup,
            hasSetupPhase: viewModel.setupPhase != nil,
            isReconfiguringSession: viewModel.state.isReconfiguringSession,
            isAwaitingHandoffSteering: viewModel.state.isAwaitingHandoffSteering,
            isHandingOffSession: viewModel.state.isHandingOffSession,
            pendingToolApprovalStatusText: viewModel.state.pendingToolApproval?.request.composerStatusText,
            isTurnActive: viewModel.turnState.isActive,
            isSendingMessage: viewModel.state.isSendingMessage
        ))
    }

    private var threadPresentation: ChatThreadPresentation {
        ChatThreadPresentation(thread: conversation.thread, providerID: providerID)
    }

    private var contextWindowCacheLookupID: String {
        threadPresentation.contextWindowCacheLookupID
    }

    private var usageSummary: ConversationUsageSummary? {
        ConversationUsageSummary.derive(
            from: events,
            cachedContextWindowSize: cachedContextWindowSize
        )
    }

    private var selectedModelBinding: Binding<String> {
        Binding(
            get: { threadPresentation.selectedModel },
            set: { viewModel.applyModelChange($0) }
        )
    }

    private var selectedEffortBinding: Binding<String> {
        Binding(
            get: { threadPresentation.selectedEffort },
            set: { viewModel.applyEffortChange($0) }
        )
    }

    private var selectedPermissionModeBinding: Binding<String> {
        Binding(
            get: { threadPresentation.selectedPermissionMode },
            set: { viewModel.applyPermissionModeChange($0) }
        )
    }

    private var selectedUseWorktreeBinding: Binding<Bool> {
        Binding(
            get: { threadPresentation.selectedUseWorktree },
            set: { viewModel.applyWorktreePreferenceChange($0) }
        )
    }

    private var showWorktreePicker: Bool {
        threadPresentation.showWorktreePicker
    }

    private var sessionLocationLabel: String? {
        threadPresentation.sessionLocationLabel
    }

    init(
        viewModel: ConversationViewModel,
        conversation: Conversation,
        composerCapabilities: ComposerCapabilities,
        defaultEnterBehavior: ThreadEnterDefaultBehavior,
        providerID: String,
        contextWindowCache: any ContextWindowCache,
        workingDirectory: String?,
        projectTrustPrompt: ProjectTrustPrompt?,
        isProjectTrustBlocked: Bool,
        onTrustProject: @escaping (ProjectTrustPrompt) -> Void,
        onDenyProjectTrust: @escaping (ProjectTrustPrompt) -> Void,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        transcriptTypography: TranscriptTypography,
        appState: AppState
    ) {
        self.viewModel = viewModel
        self.conversation = conversation
        self.composerCapabilities = composerCapabilities
        self.defaultEnterBehavior = defaultEnterBehavior
        self.providerID = providerID
        self.contextWindowCache = contextWindowCache
        self.workingDirectory = workingDirectory
        self.projectTrustPrompt = projectTrustPrompt
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.onTrustProject = onTrustProject
        self.onDenyProjectTrust = onDenyProjectTrust
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.transcriptTypography = transcriptTypography
        self.appState = appState

        let conversationID = conversation.id
        _events = Query(
            filter: #Predicate { $0.conversationId == conversationID },
            sort: \.timestamp
        )
    }

    var body: some View {
        let contentMode = displayedContentMode ?? targetContentMode
        AppKitChatSurfaceRepresentable(
            content: AnyView(
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
            ),
            composer: AnyView(ChatComposerPanel(
                viewModel: viewModel,
                composerCapabilities: composerCapabilities,
                workingDirectory: workingDirectory,
                showsTopDivider: hasVisibleChatContent && !isFollowing,
                composerMode: composerMode,
                defaultEnterBehavior: defaultEnterBehavior,
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
            ))
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .task(id: contextWindowCacheLookupID) {
            let providerID = providerID
            let selectedModel = threadPresentation.selectedModel
            cachedContextWindowSize = nil
            let size = await contextWindowCache.contextWindowSize(providerId: providerID, model: selectedModel)
            guard !Task.isCancelled else {
                return
            }
            cachedContextWindowSize = size
        }
        .focusedSceneValue(\.triggerSessionHandoffAction) {
            viewModel.triggerSessionHandoffFromCommand()
        }
    }
}

private extension ChatView {
    var targetContentMode: ChatContentMode {
        ChatContentMode.resolve(
            projectTrustPrompt: projectTrustPrompt,
            isProjectTrustBlocked: isProjectTrustBlocked,
            hasVisibleChatContent: hasVisibleChatContent
        )
    }

    @ViewBuilder
    func mainContentView(for mode: ChatContentMode) -> some View {
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
            .environment(\.transcriptTypography, transcriptTypography)
            .transition(.opacity)
        }
    }

    func sendDraft() {
        let message = viewModel.state.inputDraft
        if viewModel.submitSessionHandoffSteeringPrompt(message) {
            return
        }

        guard !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }

        let isSessionHandoffDraft = viewModel.prepareManualSessionHandoffSendIfNeeded()
        let outboundMessage = outboundMessage(from: message)

        requestScrollToBottom()
        viewModel.state.inputDraft = ""
        let retryableMessageCount = viewModel.state.retryableFailedMessageIDs.count
        Task {
            do {
                if isSessionHandoffDraft {
                    try await viewModel.sendSessionHandoffOutput(outboundMessage)
                } else {
                    try await viewModel.queueOrSend(outboundMessage)
                }
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
