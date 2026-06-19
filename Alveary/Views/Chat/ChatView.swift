import AppKit
import Foundation
import SwiftData
import SwiftUI

struct ChatView: View {
    let viewModel: ConversationViewModel
    let conversation: Conversation
    let composerCapabilities: ComposerCapabilities
    let reasoningConfiguration: ChatComposerActionRowView.ReasoningConfiguration
    let defaultEnterBehavior: ThreadEnterDefaultBehavior
    let providerID: String
    let runtimeStatus: ActivitySignal
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
    @State private var isStopConfirmationArmed = false
    @State var askUserQuestionOverlayStates: [String: AskUserQuestionOverlayState] = [:]
    @State var exitPlanModeOverlayStates: [String: ExitPlanModeOverlayState] = [:]

    private var hasVisibleChatContent: Bool {
        ChatPresentation.hasVisibleChatContent(
            hasEvents: !events.isEmpty,
            hasGroupedItems: !viewModel.state.grouper.items.isEmpty,
            hasStreamingText: viewModel.streamingText != nil
        )
    }
    var composerMode: ComposerMode {
        ChatPresentation.composerMode(for: ChatComposerModeState(
            isCancellingInitialSetup: viewModel.state.isCancellingInitialSetup,
            hasSetupPhase: viewModel.setupPhase != nil,
            isReconfiguringSession: viewModel.state.isReconfiguringSession,
            isAwaitingHandoffSteering: viewModel.state.isAwaitingHandoffSteering,
            isHandingOffSession: viewModel.state.isHandingOffSession,
            isAwaitingExitPlanModeFollowUp: viewModel.state.isAwaitingExitPlanModeFollowUp,
            pendingToolApprovalStatusText: pendingToolApprovalStatusTextForComposer,
            isTurnActive: viewModel.turnState.isActive,
            runtimeStatus: runtimeStatus,
            isSendingMessage: viewModel.state.isSendingMessage
        ))
    }

    var threadPresentation: ChatThreadPresentation {
        ChatThreadPresentation(
            thread: conversation.thread,
            providerID: providerID,
            runtimePermissionMode: viewModel.state.runtimePermissionMode,
            pendingPermissionMode: viewModel.pendingPermissionModeForDisplay(),
            runtimePlanModeEnabled: viewModel.state.runtimePlanModeEnabled,
            pendingPlanModeEnabled: viewModel.pendingPlanModeForDisplay()
        )
    }

    private var contextWindowCacheLookupID: String {
        threadPresentation.contextWindowCacheLookupID
    }

    private var usageSummary: ConversationUsageSummary? {
        ConversationUsageSummary.derive(
            from: events,
            cachedContextWindowSize: cachedContextWindowSize,
            accounting: ContextTokenAccounting(providerID: providerID)
        ) ?? .unreported
    }

    private var selectedPermissionModeBinding: Binding<String> {
        Binding(
            get: { threadPresentation.selectedPermissionMode },
            set: { viewModel.applyPermissionModeChange($0) }
        )
    }

    init(
        viewModel: ConversationViewModel,
        conversation: Conversation,
        composerCapabilities: ComposerCapabilities,
        reasoningConfiguration: ChatComposerActionRowView.ReasoningConfiguration,
        defaultEnterBehavior: ThreadEnterDefaultBehavior,
        providerID: String,
        runtimeStatus: ActivitySignal,
        contextWindowCache: any ContextWindowCache,
        workingDirectory: String?,
        projectTrustPrompt: ProjectTrustPrompt?,
        isProjectTrustBlocked: Bool,
        onTrustProject: @escaping (ProjectTrustPrompt) -> Void,
        onDenyProjectTrust: @escaping (ProjectTrustPrompt) -> Void,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        transcriptTypography: TranscriptTypography,
        appState: AppState,
        initialAskUserQuestionOverlayStates: [String: AskUserQuestionOverlayState] = [:]
    ) {
        self.viewModel = viewModel
        self.conversation = conversation
        self.composerCapabilities = composerCapabilities
        self.reasoningConfiguration = reasoningConfiguration
        self.defaultEnterBehavior = defaultEnterBehavior
        self.providerID = providerID
        self.runtimeStatus = runtimeStatus
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
        _askUserQuestionOverlayStates = State(initialValue: initialAskUserQuestionOverlayStates)

        let conversationID = conversation.id
        _events = Query(
            filter: #Predicate { $0.conversationId == conversationID },
            sort: [
                SortDescriptor(\.timestamp),
                SortDescriptor(\.id)
            ]
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
            composerConfiguration: composerPanelConfiguration
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
        .focusedSceneValue(\.chatComposerFocus, ChatComposerFocusHandle(
            claim: {
                appState.requestComposerFocus()
            },
            release: {
                appState.pendingComposerFocusToken = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        ))
        .onChange(of: composerInteractionOverlayID) { oldID, newID in
            guard oldID == nil, newID != nil else {
                return
            }
            _ = viewModel.flushDraftFromEditor()
        }
    }
}

extension ChatView {
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
        guard canUseOutboundComposerActions else {
            return
        }

        let draft = viewModel.flushDraftFromEditor()
        let message = draft.text
        if handleLocalCommandIfNeeded(draft: draft) {
            return
        }

        let steeringMessage = draft.isEffectivelyEmpty ? "" : message
        if viewModel.submitSessionHandoffSteeringPrompt(steeringMessage) {
            appState.requestComposerFocus()
            return
        }

        guard !draft.isEffectivelyEmpty else {
            return
        }

        let isSessionHandoffDraft = viewModel.prepareManualSessionHandoffSendIfNeeded()
        let outboundMessage = draft.messageText

        requestScrollToBottom()
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        let retryableMessageCount = viewModel.state.retryableFailedMessageIDs.count
        Task {
            do {
                viewModel.normalizeUnsupportedSpeedModeIfNeeded(supportsSpeedMode: composerCapabilities.supportsSpeedMode)
                if isSessionHandoffDraft {
                    try await viewModel.sendSessionHandoffOutput(outboundMessage)
                } else {
                    try await viewModel.queueOrSend(outboundMessage)
                }
            } catch is CancellationError {
                // User-initiated cancellation — rollback already restored the draft.
            } catch {
                if viewModel.state.retryableFailedMessageIDs.count == retryableMessageCount {
                    viewModel.replaceInputDraft(message, source: draft.source)
                }
                if viewModel.lastTurnError == nil {
                    viewModel.lastTurnError = error.localizedDescription
                }
            }
        }
    }

    func steerDraft() {
        guard canUseOutboundComposerActions else {
            return
        }

        let draft = viewModel.flushDraftFromEditor()
        if handleLocalCommandIfNeeded(draft: draft) {
            return
        }

        sendSteeringDraft(draft)
    }

    func alternateSteerDraft() {
        guard canUseOutboundComposerActions else {
            return
        }

        let draft = viewModel.flushDraftFromEditor()
        if handleLocalCommandIfNeeded(draft: draft) {
            return
        }

        if draft.isEffectivelyEmpty {
            guard viewModel.messageQueue.peekNext() != nil else {
                return
            }
            Task { try? await viewModel.steerNextQueuedMessage() }
            return
        }

        sendSteeringDraft(draft)
    }

    func sendSteeringDraft(_ draft: ComposerDraft) {
        guard !draft.isEffectivelyEmpty else {
            return
        }

        let message = draft.text
        let outboundMessage = draft.messageText

        requestScrollToBottom()
        clearSubmittedDraftAndRequestFocus(source: draft.source)
        Task {
            do {
                try await viewModel.steer(outboundMessage)
            } catch {
                viewModel.replaceInputDraft(message, source: draft.source)
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

    var composerPanelConfiguration: AppKitChatComposerPanelConfiguration {
        AppKitChatComposerPanelConfiguration(
            bodyConfiguration: composerBodyConfiguration,
            topContentConfiguration: composerTopContentConfiguration,
            queuedMessagesConfiguration: composerQueuedMessagesConfiguration,
            actionRowConfiguration: composerActionRowConfiguration,
            interactionOverlayConfiguration: composerInteractionOverlayConfiguration,
            showsTopDivider: hasVisibleChatContent && !isFollowing,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: ChatComposerPanelLayout.appKitHorizontalPadding,
                topContentSpacing: ChatComposerPanelLayout.topContentSpacing,
                actionRowSpacing: ChatComposerPanelLayout.actionRowSpacing,
                bottomPadding: ChatComposerPanelLayout.nativeActionRowBottomPadding
            )
        )
    }

    var composerBodyConfiguration: AppKitChatComposerBodyConfiguration {
        AppKitChatComposerBodyConfiguration(
            text: viewModel.state.inputDraft,
            draftIdentity: conversation.id,
            inputDraftRevision: viewModel.state.inputDraftRevision,
            isTextEffectivelyEmpty: viewModel.state.inputDraftIsEffectivelyEmpty,
            mode: composerMode,
            defaultEnterBehavior: defaultEnterBehavior,
            isStopConfirmationArmed: isStopConfirmationArmed,
            supportsMidTurnSteering: composerCapabilities.supportsMidTurnSteering,
            canSteerCurrentTurn: viewModel.canSteerCurrentTurn,
            isProjectTrustBlocked: isProjectTrustBlocked,
            isHandoffSteeringPromptActive: viewModel.state.isAwaitingHandoffSteering,
            isHandoffOutputPromptActive: viewModel.state.pendingHandoffOutput != nil,
            handoffSteeringCountdown: viewModel.state.handoffSteeringCountdownRemaining,
            sendCountdown: viewModel.state.handoffCountdownRemaining,
            hasQueuedMessages: !viewModel.messageQueue.pending.isEmpty,
            hasTopContent: !composerTopContentConfiguration.items.isEmpty,
            workingDirectory: workingDirectory,
            localCommands: localCommandAvailability,
            passthroughSlashCommands: passthroughSlashCommands,
            requestFirstResponder: appState.pendingComposerFocusToken,
            loadFileCompletions: loadFileCompletions,
            loadSkillCompletions: loadSkillCompletions,
            onBlockInputMutation: { isEffectivelyEmpty in
                viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: isEffectivelyEmpty)
            },
            onBlockInputDocumentChange: { document in
                viewModel.scheduleBlockInputDraftPublish(document)
            },
            onDraftSnapshotProviderChange: { provider in
                viewModel.composerDraftSnapshotProvider = provider
            },
            onSubmit: sendDraft,
            onSteer: steerDraft,
            onAlternateSteer: alternateSteerDraft,
            onStop: {
                isStopConfirmationArmed = false
                Task { await viewModel.cancel() }
            },
            onStopConfirmationChange: { isArmed in
                isStopConfirmationArmed = isArmed
            },
            onFocusRequestConsumed: { consumedToken in
                guard appState.pendingComposerFocusToken == consumedToken else {
                    return
                }
                appState.pendingComposerFocusToken = nil
            }
        )
    }

    var composerTopContentConfiguration: AppKitChatComposerTopContentView.Configuration {
        var items: [AppKitChatComposerTopContentView.Item] = []
        if let lastTurnError = viewModel.lastTurnError {
            if viewModel.canRetryFailedSessionHandoff {
                items.append(.inlineBanner(.init(
                    message: lastTurnError,
                    severity: .error,
                    actionTitle: "Retry",
                    onAction: {
                        viewModel.retryFailedSessionHandoff()
                    },
                    onDismiss: nil
                )))
            } else {
                items.append(.inlineBanner(.init(
                    message: lastTurnError,
                    severity: .error,
                    actionTitle: nil,
                    onAction: nil,
                    onDismiss: {
                        viewModel.lastTurnError = nil
                    }
                )))
            }
        }
        if let sessionContinuityNotice = viewModel.sessionContinuityNotice {
            items.append(.inlineBanner(.init(
                message: sessionContinuityNotice,
                severity: .warning,
                actionTitle: nil,
                onAction: nil,
                onDismiss: {
                    viewModel.sessionContinuityNotice = nil
                }
            )))
        }
        if let stagedContext = viewModel.stagedContext {
            items.append(.stagedContext(.init(
                context: stagedContext,
                onDismiss: {
                    viewModel.dismissStagedContext()
                }
            )))
        }
        return AppKitChatComposerTopContentView.Configuration(items: items)
    }

    var composerActionRowConfiguration: ChatComposerActionRowView.Configuration {
        let presentation = composerPresentation
        return ChatComposerActionRowView.Configuration(
            reasoning: reasoningConfiguration,
            supportedPermissionModes: ChatComposerPermissionPresentation.options(
                providerID: reasoningConfiguration.selection.providerID,
                permissionModes: composerCapabilities.supportedPermissionModes
            ),
            selectedPermissionMode: selectedPermissionModeBinding.wrappedValue,
            showWorktreePicker: showWorktreePicker,
            selectedUseWorktree: selectedUseWorktreeBinding.wrappedValue,
            isPlanModeEnabled: selectedPlanModeBinding.wrappedValue,
            isPlanModeToggleEnabled: composerCapabilities.supportsPlanMode &&
                composerCapabilities.planModeDisabledTooltip == nil &&
                !presentation.areControlsDisabled,
            planModeDisabledTooltip: composerCapabilities.planModeDisabledTooltip,
            sessionLocationLabel: sessionLocationLabel,
            usageSummary: usageSummary,
            areControlsDisabled: presentation.areControlsDisabled,
            mode: composerMode,
            primaryActionTitle: presentation.primaryActionTitle,
            primaryActionSystemImage: presentation.primaryActionSystemImage,
            isPrimaryActionDisabled: presentation.isPrimaryActionDisabled,
            isStopConfirmationArmed: isStopConfirmationArmed,
            composerActionRowHeight: ChatComposerActionRowView.defaultHeight,
            onPermissionModeChange: { selectedPermissionModeBinding.wrappedValue = $0 },
            onUseWorktreeChange: { selectedUseWorktreeBinding.wrappedValue = $0 },
            onPlanModeChange: { selectedPlanModeBinding.wrappedValue = $0 },
            onSubmit: {
                guard presentation.canSubmit else {
                    return
                }
                sendDraft()
            },
            onStop: {
                isStopConfirmationArmed = false
                Task { await viewModel.cancel() }
            }
        )
    }
}
