import AppKit
import Foundation
import Observation
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
    let isReviewTeamWorking: Bool
    let onCancelReviewTeam: () -> Void
    let contextWindowCache: any ContextWindowCache
    let workingDirectory: String?
    let projectTrustPrompt: ProjectTrustPrompt?
    let isProjectTrustBlocked: Bool
    let onTrustProject: (ProjectTrustPrompt) -> Void
    let onDenyProjectTrust: (ProjectTrustPrompt) -> Void
    let loadFileCompletions: @Sendable () async -> [String]
    let loadSkillCompletions: @Sendable () async -> [Skill]
    let settingsService: SettingsService?
    let transcriptTypography: TranscriptTypography
    let availableProjects: [Project]
    let availableSections: [SidebarSection]
    let onSelectDraftDestination: (ThreadDraftDestination) -> Void
    @Bindable var appState: AppState

    /// Optional so hosts that mount `ChatView` without the app root, such as snapshot tests,
    /// simply render no app-shot affordance. Unit tests that build `ChatView` off-hierarchy log an
    /// uninstalled-`Environment` warning when a composer configuration reads this; the read resolves
    /// to `nil`, which is exactly that no-app-root behavior, so the warning is expected.
    @Environment(AppShotCoordinator.self) var appShotCoordinator: AppShotCoordinator?

    /// Optional for the same reason as `appShotCoordinator`: a snapshot host with no app root simply
    /// offers no Sign In action on the credential banner.
    @Environment(ProviderSignInService.self) var providerSignIn: ProviderSignInService?
    @Environment(TerminalManager.self) var terminalManager: TerminalManager?

    @Query private var events: [ConversationEventRecord]
    @State private var lastScrollTime: Date = .distantPast
    @State var isFollowing = true
    @State var scrollToBottomRequest = 0
    @State private var displayedContentMode: ChatContentMode?
    @State private var cachedContextWindowSize: Int?
    @State var isStopConfirmationArmed = false
    @State var askUserQuestionOverlayStates: [String: AskUserQuestionOverlayState] = [:]
    @State var exitPlanModeOverlayStates: [String: ExitPlanModeOverlayState] = [:]
    @State var voiceInputCoordinator: ChatVoiceInputCoordinator
    @State var voiceShortcutRevalidationToken = 0
    @State var voiceSelectionRevalidationToken = 0
    @State var reasoningMenuRequestState = ReasoningMenuRequestState()

    private var hasVisibleChatContent: Bool {
        ChatPresentation.hasVisibleChatContent(
            hasEvents: events.contains(where: \.isVisibleTranscriptEvent),
            hasGroupedItems: !viewModel.state.grouper.items.isEmpty,
            hasStreamingText: viewModel.streamingText != nil ||
                viewModel.thoughtText != nil ||
                viewModel.completedThoughtText != nil
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
            isSendingMessage: viewModel.state.isSendingMessage,
            isReviewTeamWorking: isReviewTeamWorking
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

    /// Render-path only — reads the `@Query`-backed events. Resolve it in `body`'s tree and pass
    /// it down rather than reaching for it from an action or configuration builder.
    private var usageSummary: ConversationUsageSummary {
        ConversationUsageSummary.derive(
            from: events,
            cachedContextWindowSize: cachedContextWindowSize,
            accounting: ContextTokenAccounting(providerID: providerID)
        ) ?? .unreported
    }

    var selectedPermissionModeBinding: Binding<String> {
        Binding(
            get: { threadPresentation.selectedPermissionMode },
            set: {
                guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                viewModel.applyPermissionModeChange($0)
            }
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
        isReviewTeamWorking: Bool = false,
        onCancelReviewTeam: @escaping () -> Void = {},
        contextWindowCache: any ContextWindowCache,
        workingDirectory: String?,
        projectTrustPrompt: ProjectTrustPrompt?,
        isProjectTrustBlocked: Bool,
        onTrustProject: @escaping (ProjectTrustPrompt) -> Void,
        onDenyProjectTrust: @escaping (ProjectTrustPrompt) -> Void,
        loadFileCompletions: @escaping @Sendable () async -> [String],
        loadSkillCompletions: @escaping @Sendable () async -> [Skill],
        settingsService: SettingsService? = nil,
        voiceInputService: (any VoiceInputService)? = nil,
        voiceInputLifecycleController: VoiceInputLifecycleController? = nil,
        transcriptTypography: TranscriptTypography,
        availableProjects: [Project] = [],
        availableSections: [SidebarSection] = [],
        onSelectDraftDestination: @escaping (ThreadDraftDestination) -> Void = { _ in },
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
        self.isReviewTeamWorking = isReviewTeamWorking
        self.onCancelReviewTeam = onCancelReviewTeam
        self.contextWindowCache = contextWindowCache
        self.workingDirectory = workingDirectory
        self.projectTrustPrompt = projectTrustPrompt
        self.isProjectTrustBlocked = isProjectTrustBlocked
        self.onTrustProject = onTrustProject
        self.onDenyProjectTrust = onDenyProjectTrust
        self.loadFileCompletions = loadFileCompletions
        self.loadSkillCompletions = loadSkillCompletions
        self.settingsService = settingsService
        self.transcriptTypography = transcriptTypography
        self.availableProjects = availableProjects
        self.availableSections = availableSections
        self.onSelectDraftDestination = onSelectDraftDestination
        self.appState = appState
        _askUserQuestionOverlayStates = State(initialValue: initialAskUserQuestionOverlayStates)
        let resolvedVoiceService = voiceInputService ?? DisabledVoiceInputService()
        let resolvedVoiceLifecycle = voiceInputLifecycleController ?? VoiceInputLifecycleController(service: resolvedVoiceService)
        _voiceInputCoordinator = State(initialValue: ChatVoiceInputCoordinator(
            service: resolvedVoiceService,
            lifecycleController: resolvedVoiceLifecycle,
            supportedArchitecture: voiceInputService != nil && VoiceInputPlatform.isSupported,
            flushDraftFromEditor: {
                _ = viewModel.flushDraftFromEditor()
            }
        ))

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
            viewModel.triggerAutomaticSessionHandoffFromDebugMenu()
        }
        #if DEBUG
        .focusedSceneValue(\.copyAppShotPreviewAction) {
            copyAppShotDebugPreview()
        }
        #endif
        .focusedSceneValue(\.chatComposerFocus, ChatComposerFocusHandle(
            claim: {
                appState.requestComposerFocus()
            },
            release: {
                appState.pendingComposerFocusToken = nil
                NSApp.keyWindow?.makeFirstResponder(nil)
            }
        ))
        .background {
            AppWindowModalOverlayPresenter(
                modal: chatWindowModal,
                onDismiss: dismissChatWindowModal
            )
            .frame(width: 0, height: 0)
        }
        .onChange(of: composerInteractionOverlayID) { oldID, newID in
            guard oldID == nil, newID != nil else {
                return
            }
            _ = viewModel.flushDraftFromEditor()
            voiceInputCoordinator.forceStopAndCommit(reason: "Dictation stopped because the composer became unavailable.")
        }
        .onChange(of: voiceInputComposerContext) { _, newContext in
            voiceInputCoordinator.updateComposerContext(newContext)
        }
        .onChange(of: voiceInputCoordinator.modelModalState) { oldState, newState in
            if oldState != nil, newState == nil {
                appState.requestComposerFocus()
            }
        }
        .onChange(of: providerID) { _, _ in
            viewModel.disarmGoalModeIfNeeded()
        }
        .onChange(of: isProjectTrustBlocked) { _, isBlocked in
            if isBlocked {
                voiceInputCoordinator.forceStopAndCommit(reason: "Dictation stopped while project trust is required.")
                viewModel.disarmGoalModeIfNeeded()
            }
        }
        .onChange(of: composerCapabilities.supportsGoalMode) { _, supportsGoalMode in
            if !supportsGoalMode {
                viewModel.disarmGoalModeIfNeeded()
            }
        }
        .onChange(of: composerCapabilities.supportsExistingSessionGoalStart) { _, supportsExistingSessionGoalStart in
            if viewModel.hasVisibleUserMessageHistory, !supportsExistingSessionGoalStart {
                viewModel.disarmGoalModeIfNeeded()
            }
        }
        .onDisappear {
            voiceInputCoordinator.composerDidDisappear()
            viewModel.disarmGoalModeIfNeeded()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            voiceShortcutRevalidationToken &+= 1
        }
        .onReceive(NotificationCenter.default.publisher(for: .appSettingsChanged)) { _ in
            voiceShortcutRevalidationToken &+= 1
        }
    }
}

extension ChatView {
    var showsWorkspaceInEmptyState: Bool {
        ChatPresentation.showsWorkspaceInEmptyState(
            isDraft: conversation.thread?.isDraft == true,
            contentMode: displayedContentMode ?? targetContentMode,
            hasSetupPhase: viewModel.setupPhase != nil,
            isCancellingInitialSetup: viewModel.state.isCancellingInitialSetup
        )
    }

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
                isCancellingInitialSetup: viewModel.state.isCancellingInitialSetup,
                thread: conversation.thread,
                projects: availableProjects,
                sections: availableSections,
                isProjectSelectionDisabled: voiceInputCoordinator.isDraftInteractionLocked,
                onSelectDestination: { path in
                    guard !voiceInputCoordinator.isDraftInteractionLocked else { return }
                    voiceInputCoordinator.invalidatePendingActivationIntent()
                    onSelectDraftDestination(path)
                },
                workspaceConfiguration: showsWorkspaceInEmptyState ? composerTaskWorkspaceConfiguration : nil
            )
            .transition(.opacity)
        case .transcript:
            ChatTranscriptView(
                viewModel: viewModel,
                appState: appState,
                events: events,
                workingDirectory: workingDirectory,
                lastScrollTime: $lastScrollTime,
                isFollowing: $isFollowing,
                scrollToBottomRequest: $scrollToBottomRequest,
                isReviewTeamWorking: isReviewTeamWorking
            )
            .environment(\.transcriptTypography, transcriptTypography)
            .transition(.opacity)
        }
    }

    var composerPanelConfiguration: AppKitChatComposerPanelConfiguration {
        AppKitChatComposerPanelConfiguration(
            bodyConfiguration: composerBodyConfiguration,
            topContentConfiguration: composerTopContentConfiguration,
            queuedMessagesConfiguration: composerQueuedMessagesConfiguration,
            actionRowConfiguration: composerActionRowConfiguration(
                usageSummary: usageSummary, showsWorkspaceInEmptyState: showsWorkspaceInEmptyState
            ),
            interactionOverlayConfiguration: composerInteractionOverlayConfiguration,
            showsTopDivider: hasVisibleChatContent && !isFollowing,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: ChatComposerPanelLayout.appKitHorizontalPadding,
                topContentSpacing: ChatComposerPanelLayout.topContentSpacing,
                actionRowSpacing: ChatComposerPanelLayout.actionRowSpacing,
                bottomPadding: ChatComposerPanelLayout.nativeActionRowBottomPadding
            ),
            voiceInputShortcutConfiguration: voiceInputShortcutConfiguration
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
            isGoalModeArmed: viewModel.state.isGoalModeArmed,
            hasQueuedMessages: !viewModel.messageQueue.pending.isEmpty,
            hasTopContent: !composerTopContentConfiguration.items.isEmpty,
            workingDirectory: workingDirectory,
            workspaceRoots: conversation.thread?.workspaceSnapshot?.grants.map(\.path) ?? [],
            attachments: stagedComposerAttachments,
            urlOpener: openComposerEditorURL(_:),
            localCommands: localCommandAvailability,
            passthroughSlashCommands: passthroughSlashCommands,
            requestFirstResponder: appState.pendingComposerFocusToken,
            isVoiceInteractionLocked: voiceInputCoordinator.isDraftInteractionLocked,
            voiceEditorHandle: voiceInputCoordinator.editorHandle,
            onVoiceEscape: voiceInputCoordinator.cancelFromEscape,
            onVoiceInputAvailabilityChange: {
                voiceSelectionRevalidationToken &+= 1
                voiceInputCoordinator.invalidatePendingActivationIntent()
            },
            loadFileCompletions: loadFileCompletions,
            loadSkillCompletions: loadSkillCompletions,
            onOpenAttachment: openComposerAttachment(_:),
            onRemoveAttachment: removeComposerAttachment(_:),
            onBlockInputMutation: { isEffectivelyEmpty in
                viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: isEffectivelyEmpty)
            },
            onBlockInputDocumentChange: { document in
                viewModel.scheduleBlockInputDraftPublish(document)
            },
            onLocalFileURLsSelected: handleLocalFileURLsSelected(_:),
            onDraftSnapshotProviderChange: { provider in
                viewModel.composerDraftSnapshotProvider = provider
            },
            onSubmit: sendDraft,
            onSteer: steerDraft,
            onAlternateSteer: alternateSteerDraft,
            onStop: stopActiveWork,
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
}

@MainActor
@Observable
final class ReasoningMenuRequestState {
    private(set) var pendingRequest: ChatComposerActionRowView.ReasoningMenuPresentationRequest?

    func requestPresentation(section: ChatComposerActionRowView.ReasoningMenuSection = .effort) {
        pendingRequest = ChatComposerActionRowView.ReasoningMenuPresentationRequest(section: section)
    }

    func consume(_ request: UUID) {
        guard pendingRequest?.id == request else {
            return
        }
        pendingRequest = nil
    }
}
