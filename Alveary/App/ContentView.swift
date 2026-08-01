import AgentCLIKit
@preconcurrency import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) var uiModelContext
    @FocusedValue(\.newConversationAction) var newConversationAction

    let settingsService: SettingsService
    private let gitHubCLI: GitHubCLIService
    private let providerDetection: any ProviderDetectionService
    private let providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    private let agentRegistry: AgentRegistry
    private let providerRegistry: ProviderRegistry
    private let skillsService: SkillsService
    private let mcpService: MCPService
    private let agentsManager: any AgentsManager
    let agentOneShotPromptService: any AgentOneShotPromptService
    private let conversationControllerRegistry: any ConversationControllerRegistry
    private let providerSetup: ProviderSetupService
    private let contextWindowCache: any ContextWindowCache
    private let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let notificationRouter: NotificationRouter
    let threadActivityRecorder: any ThreadActivityRecording
    let gitService: GitService
    private let gitHubAttachmentImageURLResolver: GitHubAttachmentImageURLResolver
    private let voiceInputService: any VoiceInputService
    let voiceInputLifecycleController: VoiceInputLifecycleController
    @State var appUpdateManager: AppUpdateManager

    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State var isAddProjectSheetPresented = false
    @State var pendingDiskImportAfterDismiss = false
    @State private var viewModelContext: ModelContext
    @State var sidebarViewModel: SidebarViewModel
    @State var diffViewModel: DiffViewerViewModel
    @State var rightPaneWidths: RightPaneWidths
    @State var diffViewerTopSectionFraction: CGFloat
    @State var diffViewerCommitsTopSectionFraction: CGFloat
    @State var diffViewerMode: DiffViewerMode
    @State private var terminalPaneHeight: CGFloat
    @State var skillsViewModel: SkillsViewModel
    @State var mcpViewModel: MCPViewModel
    @State var scheduledTasksViewModel: ScheduledTasksViewModel
    @State var scheduledTaskProposalQueueCoordinator: ScheduledTaskProposalQueueCoordinator
    @State var pullRequestsViewModel: PullRequestsViewModel
    @State var pullRequestLinksViewModel: PullRequestLinksViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var archivedThreadsViewModel: ArchivedThreadsViewModel
    @State var onboardingViewModel: OnboardingViewModel
    @State var terminalManager = TerminalManager()
    @State var appShotCoordinator: AppShotCoordinator
    @State var appShotCaptureController: AppShotCaptureController
    @State private var toolbarProjectActions: [AlvearyProjectConfig.ProjectAction] = []
    @State private var toolbarProjectActionsThreadID: PersistentIdentifier?
    @State var diffViewerDraftRefreshRevision: UInt64 = 0
    @State var isPullRequestPopoverPresented = false
    @State var lastActiveProjectRecorder: LastActiveProjectRecorder
    @State var gitCommitModalModel: DiffGitCommitModalModel?
    @State var createPullRequestModalModel: DiffCreatePullRequestModalModel?
    // Internal so `ContentView+TerminalToolbar.swift` can own their transitions.
    @State var terminalToolbarDisplayState = TerminalToolbarDisplayState.idle
    @State var terminalToolbarTrackedSessionIDs = Set<UUID>()
    @State var terminalToolbarResetTask: Task<Void, Never>?
    @State var didAttemptLaunchSelectionRestore = false
    @State var didStartThreadActivityBackfill = false
    @State var voiceInputInteractionLockGeneration = 0

    init(component: AppComponent, appState: AppState) {
        self.init(dependencies: ContentViewDependencies.resolve(component), appState: appState)
    }

    init(dependencies: ContentViewDependencies, appState: AppState) {
        self.appState = appState
        self.settingsService = dependencies.settingsService
        self.gitHubCLI = dependencies.gitHubCLI
        self.providerDetection = dependencies.providerDetection
        self.providerDiscovery = dependencies.providerDiscovery
        self.agentRegistry = dependencies.agentRegistry
        self.providerRegistry = dependencies.providerRegistry
        self.skillsService = dependencies.skillsService
        self.mcpService = dependencies.mcpService
        self.agentsManager = dependencies.agentsManager
        self.agentOneShotPromptService = dependencies.agentOneShotPromptService
        self.conversationControllerRegistry = dependencies.conversationControllerRegistry
        self.providerSetup = dependencies.providerSetup
        self.contextWindowCache = dependencies.contextWindowCache
        self.fileListManager = dependencies.fileListManager
        self.notificationManager = dependencies.notificationManager
        self.notificationRouter = dependencies.notificationRouter
        self.threadActivityRecorder = dependencies.threadActivityRecorder
        self.gitService = dependencies.gitService
        self.gitHubAttachmentImageURLResolver = dependencies.gitHubAttachmentImageURLResolver
        self.voiceInputService = dependencies.voiceInputService
        self.voiceInputLifecycleController = dependencies.voiceInputLifecycleController
        _appUpdateManager = State(initialValue: dependencies.appUpdateManager)
        let settings = dependencies.settingsService.current
        // Keep UI mutations on the main context so sidebar `@Query` reads and view-model saves stay in sync.
        _viewModelContext = State(initialValue: dependencies.modelContainer.mainContext)
        _rightPaneWidths = State(initialValue: RightPaneWidths(settings: settings))
        _diffViewerTopSectionFraction = State(initialValue: CGFloat(settings.diffViewerTopSectionFraction))
        _diffViewerCommitsTopSectionFraction = State(initialValue: CGFloat(settings.diffViewerCommitsTopSectionFraction))
        _diffViewerMode = State(initialValue: settings.diffViewerMode)
        _terminalPaneHeight = State(initialValue: CGFloat(settings.terminalPaneHeight))
        let bootstrapState = Self.makeBootstrapState(dependencies: dependencies, appState: appState)
        _sidebarViewModel = State(initialValue: bootstrapState.sidebarViewModel)
        _skillsViewModel = State(initialValue: SkillsViewModel(skillsService: dependencies.skillsService))
        _mcpViewModel = State(initialValue: MCPViewModel(mcpService: dependencies.mcpService))
        _scheduledTasksViewModel = State(initialValue: Self.makeScheduledTasksViewModel(dependencies: dependencies))
        _scheduledTaskProposalQueueCoordinator = State(
            initialValue: Self.makeScheduledTaskProposalQueueCoordinator(dependencies: dependencies)
        )
        _pullRequestsViewModel = State(initialValue: Self.makePullRequestsViewModel(dependencies: dependencies, appState: appState))
        _pullRequestLinksViewModel = State(initialValue: Self.makePullRequestLinksViewModel(dependencies: dependencies))
        _settingsViewModel = State(initialValue: Self.makeSettingsViewModel(dependencies: dependencies))
        _archivedThreadsViewModel = State(initialValue: Self.makeArchivedThreadsViewModel(
            dependencies: dependencies, sidebarViewModel: bootstrapState.sidebarViewModel, appState: appState
        ))
        _onboardingViewModel = State(initialValue: Self.makeOnboardingViewModel(dependencies: dependencies))
        _appShotCoordinator = State(initialValue: bootstrapState.appShotCoordinator)
        _appShotCaptureController = State(initialValue: bootstrapState.appShotCaptureController)
        _lastActiveProjectRecorder = State(initialValue: bootstrapState.lastActiveProjectRecorder)
        _diffViewModel = State(initialValue: bootstrapState.diffViewModel)
    }

    var body: some View {
        let resolvedRightPaneDestination = rightPaneDestination
        let widthDomain = resolvedRightPaneDestination?.widthDomain ?? .diff
        let diffRoutingKey = diffViewerRoutingKey
        let middlePane = MiddlePane(
            appState: appState,
            modelContext: viewModelContext,
            gitHubCLI: gitHubCLI,
            agentsManager: agentsManager,
            conversationControllerRegistry: conversationControllerRegistry,
            settingsService: settingsService,
            providerRegistry: providerRegistry,
            providerDiscovery: providerDiscovery,
            providerSetup: providerSetup,
            contextWindowCache: contextWindowCache,
            fileListManager: fileListManager,
            notificationManager: notificationManager,
            voiceInputService: voiceInputService,
            voiceInputLifecycleController: voiceInputLifecycleController,
            sidebarViewModel: sidebarViewModel,
            loadInstalledSkills: { [skillsService] in
                (try? await skillsService.loadInstalled()) ?? []
            },
            diffViewModel: diffViewModel,
            diffViewerSwitchScope: { self.diffViewerSwitchScope },
            skillsViewModel: skillsViewModel,
            mcpViewModel: mcpViewModel,
            scheduledTasksViewModel: scheduledTasksViewModel,
            pullRequestsViewModel: pullRequestsViewModel,
            settingsViewModel: settingsViewModel,
            archivedThreadsViewModel: archivedThreadsViewModel,
            appUpdateManager: appUpdateManager,
            targetSettingsPage: appState.pendingSettingsTargetPage,
            onTargetSettingsPageHandled: { page in
                appState.clearPendingSettingsTargetPage(page)
            }
        )

        let rootWindowView = NavigationSplitView(columnVisibility: $splitVisibility) {
            SidebarView(
                viewModel: sidebarViewModel,
                appState: appState,
                voiceInputLifecycleController: voiceInputLifecycleController
            )
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            ZStack(alignment: .bottom) {
                ResizableRightPane(
                    destination: resolvedRightPaneDestination,
                    width: rightPaneWidthBinding(for: widthDomain),
                    onWidthCommit: { width in
                        persistRightPaneWidth(width, domain: widthDomain)
                    },
                    presentationGeneration: rightPanePresentationGeneration,
                    dismissalRequests: rightPaneDismissalRequests,
                    onDeactivate: deactivateRightPane,
                    onDismiss: dismissRightPane,
                    mainContent: { middlePane },
                    paneContent: rightPaneContent
                )

                if appState.isTerminalPaneVisible {
                    TerminalPane(
                        height: $terminalPaneHeight,
                        onHeightCommit: persistTerminalPaneHeight,
                        canViewThread: canViewThread,
                        onViewThread: viewThread,
                        onNewShell: {
                            createTerminalShellSession(focus: true)
                        },
                        onClose: appState.hideTerminalPane
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(1)
                }
            }
            .clipped()
            .overlay(alignment: .top) {
                AppSeparatorHairline(surface: .titlebar)
            }
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: appState.isTerminalPaneVisible)
        }
        .environment(terminalManager)
        .environment(appShotCoordinator)
        .task {
            appShotCoordinator.start(settingsService: settingsService)
        }
        .task {
            appUpdateManager.startAutomaticChecks()
        }
        .task {
            onboardingViewModel.start()
        }
        .overlay(alignment: .bottom, content: errorToastOverlay)
        .appUpdateRestartAlert(
            updateManager: appUpdateManager,
            isSuppressed: isVoiceInputInteractionLocked
        )
        .appWindowChromeConfigured()
        .background {
            AppWindowModalOverlayPresenter(
                modal: rootWindowModal,
                onDismiss: dismissRootWindowModal
            )
            .frame(width: 0, height: 0)
        }
        .toolbar(removing: .title)
        .toolbar {
            ToolbarItem(id: MainWindowToolbarItemID.header, placement: .navigation) {
                MainPaneToolbarHeader(
                    presentation: MainPaneHeaderPresentation(selection: appState.selectedSidebarItem),
                    onNewConversation: headerNewConversationAction
                )
                .padding(.leading, MainPaneToolbarLayout.leadingPadding)
            }
            .sharedBackgroundVisibility(.hidden)

            ToolbarSpacer(.flexible)

            ToolbarItem(id: MainWindowToolbarItemID.actions, placement: .primaryAction) {
                PrimaryToolbarButtonGroup(
                    selectedThreadID: selectedThreadID,
                    projectActions: toolbarProjectActions,
                    projectActionsThreadID: toolbarProjectActionsThreadID,
                    terminalTitle: terminalToggleTitle,
                    terminalDisplayState: terminalToolbarDisplayState,
                    terminalHelpText: "\(terminalToggleTitle) (\(KeyboardShortcut.toggleTerminalPane.displayString))",
                    pullRequestState: pullRequestLinksToolbarState,
                    pullRequestHelpText: pullRequestToolbarHelpText,
                    isPullRequestPopoverPresented: $isPullRequestPopoverPresented,
                    diffDisplayState: diffViewerToolbarDisplayState,
                    diffHelpText: diffViewerToggleHelpText
                        + " (\(KeyboardShortcut.toggleDiffViewer.displayString))",
                    diffAccessibilityLabel: isDiffViewerRendered ? "Hide Diff Viewer" : "Show Diff Viewer",
                    diffAccessibilityValue: diffViewerToggleAccessibilityValue,
                    settingsBadgeState: appUpdateManager.toolbarBadgeState,
                    onProjectAction: { threadID, action in
                        runProjectAction(threadID: threadID, action: action)
                    },
                    onToggleTerminal: toggleTerminalPane,
                    onPullRequestAction: performPullRequestToolbarAction,
                    onPullRequestSecondaryAction: presentPullRequestPopover,
                    pullRequestPopoverContent: { AnyView(pullRequestPopoverContent()) },
                    onToggleDiffViewer: toggleDiffViewer,
                    onOpenSettings: {
                        appState.openSettings(targetPage: appUpdateManager.toolbarBadgeState.settingsTargetPage)
                    }
                )
                .padding(.trailing, MainPaneToolbarLayout.trailingPadding)
            }
            .sharedBackgroundVisibility(.hidden)
        }

        let selectionObservedView = rootWindowView
        .onChange(of: appState.isLeftPaneVisible) { _, isVisible in
            splitVisibility = isVisible ? .all : .detailOnly
        }
        .onChange(of: splitVisibility) { _, visibility in
            appState.setLeftPaneVisible(visibility != .detailOnly)
        }
        .onChange(of: appState.selectedSidebarItem) { _, selection in
            scheduleLastActiveProjectRecord(for: selection)
            appState.invalidateCommitMessageGenerationForSelectionChange()
        }
        .onChange(of: appState.selectedConversationIDs) { _, _ in
            appState.invalidateCommitMessageGenerationForSelectionChange()
        }
        .onChange(of: appShotCoordinator.triggerID) { _, _ in
            appShotCaptureController.captureIfIdle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .threadDraftProjectChanged)) { _ in
            diffViewerDraftRefreshRevision &+= 1
            Task { await refreshToolbarProjectActions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .threadDraftMaterialized)) { _ in
            diffViewerDraftRefreshRevision &+= 1
            Task { await refreshToolbarProjectActions() }
        }
        // Watching follows the rendered pane; routing is owned by the keyed task below.
        .onChange(of: isDiffViewerRendered, initial: true) { _, isRendered in
            diffViewModel.setWatchingEnabled(isRendered)
        }
        // A state change inside the pane (merge, close, reopen, ready for review)
        // refetches the detail; mirror it into the stored link so the toolbar
        // glyph updates without waiting for the pane to be reopened.
        .onChange(of: activeSelectionPullRequestStatus) { _, _ in
            persistActiveSelectionPullRequestStatus()
        }
        // Disabling the integration removes every way back to an open pull-request
        // pane, so forget it rather than leaving a session that would reappear.
        .onChange(of: settingsService.current.pullRequestsEnabled) { _, isEnabled in
            guard !isEnabled else {
                return
            }
            pullRequestsViewModel.deactivatePane()
        }
        .task(id: diffRoutingKey) {
            await routeDiffViewer(key: diffRoutingKey)
        }

        let activityObservedView = selectionObservedView
        .onChange(of: appState.pendingCommand) { _, command in
            handlePendingCommand(command)
        }
        .onChange(of: notificationRouter.pendingConversationId) { _, newValue in
            routePendingConversationIfModelPreparationAllows(newValue)
        }
        .onChange(of: notificationRouter.pendingScheduledTaskDefinitionId) { _, definitionID in
            routePendingScheduledTaskIfModelPreparationAllows(definitionID)
        }
        .onChange(of: terminalManager.runningProjectActionSessionIDs, initial: true) { _, runningSessionIDs in
            handleTerminalRunningSessionIDsChange(runningSessionIDs)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            onboardingViewModel.handleAppDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(
            for: .voiceInputComposerInteractionLockChanged,
            object: voiceInputLifecycleController
        )) { _ in
            voiceInputInteractionLockGeneration &+= 1
            replayModelPreparationDeferredRoutingIfAvailable()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            terminalManager.terminateAllSessions()
        }

        // The create-pull-request sheet is a lifted helper (type-check budget);
        // it hosts the third `.sheet` in this chain.
        return createPullRequestSheetHost(
            activityObservedView
            .sheet(
                isPresented: $isAddProjectSheetPresented,
                // Wait for the sheet's dismissal to finish before opening the
                // `NSOpenPanel`, otherwise the modal pops on top of the still-animating
                // sheet and stutters the UI.
                onDismiss: handleAddProjectSheetDismiss,
                content: addProjectSheetContent
            )
            .sheet(item: $gitCommitModalModel) { model in
                DiffGitCommitModal(model: model) {
                    gitCommitModalModel = nil
                }
            }
        )
        .preferredColorScheme(colorScheme(for: settingsViewModel.theme))
        .task(id: selectedThreadID) {
            await refreshToolbarProjectActions()
        }
        .onAppear {
            wireNotificationManager()
            wireMarkdownImageFallbackResolver()
            startThreadActivityBackfillIfNeeded()
            restoreLastOpenThreadSelectionIfNeeded()
            replayModelPreparationDeferredRoutingIfAvailable()
            // Mark-read of the active conversation is handled by `ThreadDetailView` once
            // the restored selection mounts; just sync the dock badge on launch.
            notificationManager.refreshBadgeCount()
        }
        // Publish the terminal-toggle action so the ⇧⌘T menu item in
        // `AlvearyApp.commands` runs the same default-shell-then-flip sequence
        // as the toolbar button — `terminalManager` is view-local `@State`, so
        // the menu needs a `FocusedValue` hop to reach it.
        .focusedSceneValue(\.toggleTerminalPaneAction, toggleTerminalPane)
        .focusedSceneValue(\.diffViewerCommand, diffViewerCommand)
        // Nil while the button is hidden, which is what greys out the menu item.
        .focusedSceneValue(
            \.togglePullRequestsAction,
            pullRequestLinksToolbarState == nil ? nil : performPullRequestToolbarAction
        )
    }
}

private extension ContentView {
    /// Lets the shared markdown image store mint signed GitHub attachment URLs
    /// when a direct fetch fails (session-gated assets; private repositories).
    func wireMarkdownImageFallbackResolver() {
        let resolver = gitHubAttachmentImageURLResolver
        AppMarkdownImageStore.shared.remoteFallbackURLProvider = { source in
            await resolver.resolveSignedURL(forSource: source)
        }
    }

    var isVoiceInputInteractionLocked: Bool {
        _ = voiceInputInteractionLockGeneration
        return voiceInputLifecycleController.isComposerInteractionLocked
    }

    func colorScheme(for theme: String) -> ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    func refreshToolbarProjectActions() async {
        guard let threadID = selectedThreadID else {
            toolbarProjectActions = []
            toolbarProjectActionsThreadID = nil
            return
        }

        await Task.yield()

        guard case .thread(let selectedThread) = appState.selectedSidebarItem,
              selectedThread.persistentModelID == threadID,
              let thread = uiModelContext.resolveThread(id: threadID),
              thread.archivedAt == nil,
              !thread.isDraft,
              thread.effectiveMode == .project,
              let projectPath = thread.project?.path else {
            guard selectedThreadID == threadID else { return }
            toolbarProjectActions = []
            toolbarProjectActionsThreadID = nil
            return
        }

        let config = await AlvearyProjectConfig(projectPath: projectPath)

        guard selectedThreadID == threadID else {
            return
        }

        toolbarProjectActions = config.actions ?? []
        toolbarProjectActionsThreadID = threadID
    }

}
