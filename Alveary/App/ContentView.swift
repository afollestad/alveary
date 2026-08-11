import AgentCLIKit
@preconcurrency import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) var uiModelContext
    @Environment(\.openWindow) private var openWindow
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
    let menuBarCommandRouter: MenuBarCommandRouter
    let mainWindowPresenter: MainWindowPresenter
    /// App-scoped, so the capture shortcut it registers survives the window closing.
    let appShotCoordinator: AppShotCoordinator
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
    @State var rightPaneWidth: CGFloat
    @State var diffViewerTopSectionFraction: CGFloat
    @State var diffViewerCommitsTopSectionFraction: CGFloat
    @State var diffViewerMode: DiffViewerMode
    @State private var terminalPaneHeight: CGFloat
    @State var skillsViewModel: SkillsViewModel
    @State var mcpViewModel: MCPViewModel
    @State var scheduledTasksViewModel: ScheduledTasksViewModel
    @State var scheduledTaskProposalQueueCoordinator: ScheduledTaskProposalQueueCoordinator
    @State var pullRequestReviewProposalCoordinator: PullRequestReviewProposalCoordinator
    @State var unresolvedApprovalRegistry: UnresolvedApprovalRegistry
    @State var pullRequestsViewModel: PullRequestsViewModel
    @State var pullRequestLinksViewModel: PullRequestLinksViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var archivedThreadsViewModel: ArchivedThreadsViewModel
    @State var onboardingViewModel: OnboardingViewModel
    @State var terminalManager = TerminalManager()
    @State var appShotCaptureController: AppShotCaptureController
    // Internal so `ContentView+RootToolbar.swift` can build the button group.
    @State var toolbarProjectActions: [AlvearyProjectConfig.ProjectAction] = []
    @State var toolbarProjectActionsOwner: ToolbarProjectActionsOwner?
    @State var diffViewerDraftRefreshRevision: UInt64 = 0
    @State var isPullRequestPopoverPresented = false
    @State var lastActiveProjectRecorder: LastActiveProjectRecorder
    @State var gitCommitModalModel: DiffGitCommitModalModel?
    @State var createPullRequestModalModel: DiffCreatePullRequestModalModel?
    // Internal so `ContentView+TerminalToolbar.swift` can own their transitions.
    @State var terminalToolbarDisplayState = TerminalToolbarDisplayState.idle
    @State var terminalToolbarTrackedSessionIDs = Set<UUID>()
    @State var terminalToolbarResetTask: Task<Void, Never>?
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
        self.menuBarCommandRouter = dependencies.menuBarCommandRouter
        self.mainWindowPresenter = dependencies.mainWindowPresenter
        self.appShotCoordinator = dependencies.appShotCoordinator
        self.threadActivityRecorder = dependencies.threadActivityRecorder
        self.gitService = dependencies.gitService
        self.gitHubAttachmentImageURLResolver = dependencies.gitHubAttachmentImageURLResolver
        self.voiceInputService = dependencies.voiceInputService
        self.voiceInputLifecycleController = dependencies.voiceInputLifecycleController
        _appUpdateManager = State(initialValue: dependencies.appUpdateManager)
        let settings = dependencies.settingsService.current
        // Keep UI mutations on the main context so sidebar `@Query` reads and view-model saves stay in sync.
        _viewModelContext = State(initialValue: dependencies.modelContainer.mainContext)
        _rightPaneWidth = State(initialValue: CGFloat(settings.rightPaneWidth))
        _diffViewerTopSectionFraction = State(initialValue: CGFloat(settings.diffViewerTopSectionFraction))
        _diffViewerCommitsTopSectionFraction = State(initialValue: CGFloat(settings.diffViewerCommitsTopSectionFraction))
        _diffViewerMode = State(initialValue: settings.diffViewerMode)
        _terminalPaneHeight = State(initialValue: CGFloat(settings.terminalPaneHeight))
        let bootstrapState = Self.makeBootstrapState(dependencies: dependencies, appState: appState)
        _sidebarViewModel = State(initialValue: bootstrapState.sidebarViewModel)
        _skillsViewModel = State(initialValue: SkillsViewModel(skillsService: dependencies.skillsService))
        _mcpViewModel = State(initialValue: MCPViewModel(mcpService: dependencies.mcpService))
        _scheduledTasksViewModel = State(initialValue: Self.makeScheduledTasksViewModel(dependencies: dependencies))
        _scheduledTaskProposalQueueCoordinator = State(initialValue: bootstrapState.scheduledTaskProposalQueueCoordinator)
        _pullRequestReviewProposalCoordinator = State(initialValue: bootstrapState.reviewProposalCoordinator)
        _unresolvedApprovalRegistry = State(initialValue: Self.makeUnresolvedApprovalRegistry(dependencies: dependencies))
        _pullRequestsViewModel = State(initialValue: bootstrapState.pullRequestsViewModel)
        _pullRequestLinksViewModel = State(initialValue: Self.makePullRequestLinksViewModel(dependencies: dependencies))
        _settingsViewModel = State(initialValue: Self.makeSettingsViewModel(dependencies: dependencies))
        _archivedThreadsViewModel = State(initialValue: bootstrapState.archivedThreadsViewModel)
        _onboardingViewModel = State(initialValue: Self.makeOnboardingViewModel(dependencies: dependencies))
        _appShotCaptureController = State(initialValue: bootstrapState.appShotCaptureController)
        _lastActiveProjectRecorder = State(initialValue: bootstrapState.lastActiveProjectRecorder)
        _diffViewModel = State(initialValue: bootstrapState.diffViewModel)
    }

    var body: some View {
        // Every group below is its own type-check scope; see the type-check budget
        // bullets in `Alveary/Views/AGENTS.md`.
        rootSheetHost(rootActivityObservers(rootSelectionObservers(rootWindowView)))
            .preferredColorScheme(colorScheme(for: settingsViewModel.theme))
            .task(id: toolbarProjectActionsSelection) {
                await refreshToolbarProjectActions()
            }
            // Warms the Pull Requests screen's first visit from here rather than from the screen,
            // which only appears once the user has already navigated to it. Shares the screen's
            // freshness throttle, so this is one load and not a second path.
            .task {
                await pullRequestsViewModel.prefetchAtLaunch()
            }
            .onAppear {
                // The scene can be re-created after the user closes it, and only the view tree
                // can hand AppKit an action that rebuilds it.
                mainWindowPresenter.register { openWindow(id: MainWindowPresenter.sceneID) }
                wireNotificationManager()
                wireMarkdownImageFallbackResolver()
                startThreadActivityBackfillIfNeeded()
                restoreLastOpenThreadSelectionIfNeeded()
                replayModelPreparationDeferredRoutingIfAvailable()
                reportRecoveredModelStoreIfNeeded()
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

/// The root window's view tree, split into one helper per modifier group so no
/// single getter carries the whole hierarchy's type-check cost.
private extension ContentView {
    var middlePane: MiddlePane {
        MiddlePane(
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
    }

    var rootWindowView: some View {
        rootWindowChrome(
            NavigationSplitView(columnVisibility: $splitVisibility) {
                SidebarView(
                    viewModel: sidebarViewModel,
                    appState: appState,
                    voiceInputLifecycleController: voiceInputLifecycleController
                )
                    .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
            } detail: {
                rootDetailPane
            }
        )
    }

    var rootDetailPane: some View {
        // Built here rather than inside `mainContent` so its observation reads stay
        // on this body evaluation, as they were when `body` constructed it directly.
        let mainPane = middlePane
        let resolvedRightPaneDestination = rightPaneDestination

        return ZStack(alignment: .bottom) {
            ResizableRightPane(
                destination: resolvedRightPaneDestination,
                width: $rightPaneWidth,
                onWidthCommit: persistRightPaneWidth,
                presentationGeneration: rightPanePresentationGeneration,
                dismissalRequests: rightPaneDismissalRequests,
                onDeactivate: deactivateRightPane,
                onDismiss: dismissRightPane,
                mainContent: { mainPane.equatable() },
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

    func rootWindowChrome<Content: View>(_ content: Content) -> some View {
        content
        .environment(terminalManager)
        .environment(appShotCoordinator)
        // Scheduling proposals are confirmed inside transcript widgets, so the queue
        // coordinator and its editor drafts have to reach the chat surface.
        .environment(scheduledTaskProposalQueueCoordinator)
        .environment(scheduledTasksViewModel)
        // Review submissions are confirmed inside transcript widgets too.
        .environment(pullRequestReviewProposalCoordinator)
        // Sidebar rows and conversation-tab chips read this for the waiting dot.
        .environment(unresolvedApprovalRegistry)
        .task {
            // Deliberately not in its `init`: it scans the event store, and `init` runs during
            // `ContentView` construction. A dot a frame late beats a slower launch.
            unresolvedApprovalRegistry.start()
        }
        .task {
            appUpdateManager.startAutomaticChecks()
        }
        .task {
            onboardingViewModel.start()
            // Onboarding owns the screen on first launch; asking behind its modal is pointless.
            guard !onboardingViewModel.isPresented else {
                return
            }
            await notificationManager.requestAuthorizationIfNeeded()
        }
        .onChange(of: onboardingViewModel.isPresented) { _, isPresented in
            guard !isPresented else {
                return
            }
            Task { await notificationManager.requestAuthorizationIfNeeded() }
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
        // macOS 27 gives the toolbar its own elevated fill on the pane screens — measured ~10
        // levels lighter than the window background the header and content beneath it draw on —
        // though not on the AppKit-hosted transcript. Hiding it makes the toolbar defer to that
        // same background, so the chrome stays one band split only by `AppSeparatorHairline`.
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            rootToolbarContent
        }
    }

    /// Both selection-driven observer groups, composed in the order the chain had
    /// when it was one run of modifiers.
    func rootSelectionObservers<Content: View>(_ content: Content) -> some View {
        rootRoutingObservers(rootLayoutObservers(content))
    }

    func rootLayoutObservers<Content: View>(_ content: Content) -> some View {
        content
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
        .onChange(of: appShotCoordinator.pendingTriggerID) { _, _ in
            drainPendingAppShotCapture()
        }
    }

    func rootRoutingObservers<Content: View>(_ content: Content) -> some View {
        let diffRoutingKey = diffViewerRoutingKey

        return content
        .onReceive(NotificationCenter.default.publisher(for: .threadDraftProjectChanged)) { _ in
            diffViewerDraftRefreshRevision &+= 1
            Task { await refreshToolbarProjectActions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .threadDraftMaterialized)) { _ in
            diffViewerDraftRefreshRevision &+= 1
            Task { await refreshToolbarProjectActions() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .projectConfigDidChange)) { notification in
            refreshToolbarProjectActionsIfConfigChanged(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pullRequestLinkRequested)) { notification in
            handlePullRequestLinkRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pullRequestPaneRequested)) { notification in
            handlePullRequestPaneRequest(notification)
        }
        .onReceive(NotificationCenter.default.publisher(for: .threadOpenRequested)) { notification in
            handleThreadOpenRequest(notification)
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
    }

    func rootActivityObservers<Content: View>(_ content: Content) -> some View {
        content
        .onChange(of: appState.pendingCommand) { _, command in
            handlePendingCommand(command)
        }
        .onChange(of: menuBarCommandRouter.pendingCommand) { _, command in
            routePendingMenuBarCommandIfModelPreparationAllows(command)
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
    }

    func rootSheetHost<Content: View>(_ content: Content) -> some View {
        // The create-pull-request sheet is a lifted helper (type-check budget);
        // it hosts the third `.sheet` in this chain.
        createPullRequestSheetHost(
            content
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
}
