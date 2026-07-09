import AgentCLIKit
@preconcurrency import AppKit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) var uiModelContext

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
    private let runtimeStore: any ConversationRuntimeStore
    private let keepAwakeService: KeepAwakeService
    private let worktreeManager: WorktreeManager
    private let providerSetup: ProviderSetupService
    private let contextWindowCache: any ContextWindowCache
    private let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let notificationRouter: NotificationRouter
    let threadActivityRecorder: any ThreadActivityRecording
    let gitService: GitService
    @State var appUpdateManager: AppUpdateManager

    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State var isAddProjectSheetPresented = false
    @State var pendingDiskImportAfterDismiss = false
    @State private var viewModelContext: ModelContext
    @State var sidebarViewModel: SidebarViewModel
    @State var diffViewModel: DiffViewerViewModel
    @State var diffViewerWidth: CGFloat
    @State var diffViewerTopSectionFraction: CGFloat
    @State var diffViewerCommitsTopSectionFraction: CGFloat
    @State var diffViewerMode: DiffViewerMode
    @State private var terminalPaneHeight: CGFloat
    @State private var skillsViewModel: SkillsViewModel
    @State private var mcpViewModel: MCPViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State var onboardingViewModel: OnboardingViewModel
    @State var terminalManager: TerminalManager
    @State var appShotCoordinator: AppShotCoordinator
    @State private var toolbarProjectActions: [AlvearyProjectConfig.ProjectAction]
    @State private var toolbarProjectActionsThreadID: PersistentIdentifier?
    @State var diffViewerSwitchGeneration = 0
    @State var gitCommitModalModel: DiffGitCommitModalModel?
    @State private var terminalToolbarDisplayState = TerminalToolbarDisplayState.idle
    @State private var terminalToolbarTrackedSessionIDs = Set<UUID>()
    @State private var terminalToolbarResetTask: Task<Void, Never>?
    @State var didAttemptLaunchSelectionRestore = false
    @State var didStartThreadActivityBackfill = false

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
        self.runtimeStore = dependencies.runtimeStore
        self.keepAwakeService = dependencies.keepAwakeService
        self.worktreeManager = dependencies.worktreeManager
        self.providerSetup = dependencies.providerSetup
        self.contextWindowCache = dependencies.contextWindowCache
        self.fileListManager = dependencies.fileListManager
        self.notificationManager = dependencies.notificationManager
        self.notificationRouter = dependencies.notificationRouter
        self.threadActivityRecorder = dependencies.threadActivityRecorder
        self.gitService = dependencies.gitService
        _appUpdateManager = State(initialValue: dependencies.appUpdateManager)
        let settings = dependencies.settingsService.current
        // Keep UI mutations on the container's main context so sidebar `@Query` reads
        // and imperative view-model saves stay in sync without requiring a relaunch.
        _viewModelContext = State(initialValue: dependencies.modelContainer.mainContext)
        _diffViewerWidth = State(initialValue: CGFloat(settings.diffViewerWidth))
        _diffViewerTopSectionFraction = State(initialValue: CGFloat(settings.diffViewerTopSectionFraction))
        _diffViewerCommitsTopSectionFraction = State(initialValue: CGFloat(settings.diffViewerCommitsTopSectionFraction))
        _diffViewerMode = State(initialValue: settings.diffViewerMode)
        _terminalPaneHeight = State(initialValue: CGFloat(settings.terminalPaneHeight))
        _sidebarViewModel = State(initialValue: Self.makeSidebarViewModel(dependencies: dependencies, appState: appState))
        _diffViewModel = State(initialValue: Self.makeDiffViewModel(dependencies: dependencies))
        _skillsViewModel = State(initialValue: SkillsViewModel(skillsService: dependencies.skillsService))
        _mcpViewModel = State(initialValue: MCPViewModel(mcpService: dependencies.mcpService))
        _settingsViewModel = State(initialValue: Self.makeSettingsViewModel(dependencies: dependencies))
        _onboardingViewModel = State(
            initialValue: OnboardingViewModel(
                settingsService: dependencies.settingsService,
                dependencyService: dependencies.onboardingDependencyService
            )
        )
        _terminalManager = State(initialValue: TerminalManager())
        _appShotCoordinator = State(initialValue: AppShotCoordinator())
        _toolbarProjectActions = State(initialValue: [])
        _toolbarProjectActionsThreadID = State(initialValue: nil)
    }

    private static func makeSidebarViewModel(dependencies: ContentViewDependencies, appState: AppState) -> SidebarViewModel {
        SidebarViewModel(
            agentsManager: dependencies.agentsManager,
            modelContext: dependencies.modelContainer.mainContext,
            shell: dependencies.shellRunner,
            gitHubCLI: dependencies.gitHubCLI,
            worktreeManager: dependencies.worktreeManager,
            settingsService: dependencies.settingsService,
            providerDiscovery: dependencies.providerDiscovery,
            providerSessionActions: dependencies.providerSessionActions,
            presentUnexpectedError: { message in
                appState.presentUnexpectedError(message: message)
            },
            notificationManager: dependencies.notificationManager,
            threadActivityRecorder: dependencies.threadActivityRecorder
        )
    }

    private static func makeDiffViewModel(dependencies: ContentViewDependencies) -> DiffViewerViewModel {
        DiffViewerViewModel(
            gitService: dependencies.gitService,
            diffStore: dependencies.diffWorkspaceStore,
            fileListManager: dependencies.fileListManager,
            agentsManager: dependencies.agentsManager
        )
    }

    private static func makeSettingsViewModel(dependencies: ContentViewDependencies) -> SettingsViewModel {
        let soundPreviewer = SettingsSoundPreviewer()
        return SettingsViewModel(
            settingsService: dependencies.settingsService,
            providerDiscovery: dependencies.providerDiscovery,
            agentRegistry: dependencies.agentRegistry,
            soundPreviewer: soundPreviewer.play
        )
    }

    var body: some View {
        let middlePane = MiddlePane(
            appState: appState,
            modelContext: viewModelContext,
            gitHubCLI: gitHubCLI,
            agentsManager: agentsManager,
            runtimeStore: runtimeStore,
            keepAwakeService: keepAwakeService,
            settingsService: settingsService,
            providerRegistry: providerRegistry,
            providerDiscovery: providerDiscovery,
            worktreeManager: worktreeManager,
            providerSetup: providerSetup,
            contextWindowCache: contextWindowCache,
            fileListManager: fileListManager,
            notificationManager: notificationManager,
            threadActivityRecorder: threadActivityRecorder,
            sidebarViewModel: sidebarViewModel,
            loadInstalledSkills: { [skillsService] in
                (try? await skillsService.loadInstalled()) ?? []
            },
            diffViewModel: diffViewModel,
            skillsViewModel: skillsViewModel,
            mcpViewModel: mcpViewModel,
            settingsViewModel: settingsViewModel,
            appShotCoordinator: appShotCoordinator,
            appUpdateManager: appUpdateManager,
            targetSettingsPage: appState.pendingSettingsTargetPage,
            onTargetSettingsPageHandled: { page in
                appState.clearPendingSettingsTargetPage(page)
            }
        )

        NavigationSplitView(columnVisibility: $splitVisibility) {
            SidebarView(viewModel: sidebarViewModel, appState: appState)
                .navigationSplitViewColumnWidth(min: 280, ideal: 320, max: 380)
        } detail: {
            ZStack(alignment: .bottom) {
                GeometryReader { proxy in
                    let effectiveDiffViewerWidth = effectiveDiffViewerWidth(availableWidth: proxy.size.width)
                    let diffViewerWidthBinding = Binding(
                        get: { effectiveDiffViewerWidth },
                        set: { diffViewerWidth = $0 }
                    )
                    let effectiveDiffViewerBounds = effectiveDiffViewerBounds(availableWidth: proxy.size.width)

                    HStack(spacing: 0) {
                        middlePane
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .clipped()

                        if appState.isRightPaneVisible {
                            ContentDiffViewerResizeHandle(
                                width: diffViewerWidthBinding,
                                bounds: effectiveDiffViewerBounds,
                                onCommit: persistDiffViewerWidth
                            )
                            DiffViewerPane(
                                viewModel: diffViewModel,
                                // Keep render-time gates observation-tracked; action handlers re-resolve backing rows.
                                canCommit: appState.selectedSidebarItem?.canCommitDiffChanges == true,
                                mode: $diffViewerMode,
                                onModeCommit: persistDiffViewerMode,
                                topSectionFraction: activeDiffViewerTopSectionFraction,
                                onTopSectionFractionCommit: { fraction in
                                    persistDiffViewerTopSectionFraction(fraction, mode: diffViewerMode)
                                },
                                onCommitRequested: presentGitCommitModal
                            )
                            .frame(width: effectiveDiffViewerWidth)
                        }
                    }
                }
                .animation(.easeInOut(duration: 0.25), value: appState.isRightPaneVisible)

                if appState.isTerminalPaneVisible {
                    TerminalPane(
                        height: $terminalPaneHeight,
                        onHeightCommit: persistTerminalPaneHeight,
                        visibleThreadID: visibleThreadID,
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
            .animation(.spring(response: 0.32, dampingFraction: 0.9), value: appState.isTerminalPaneVisible)
        }
        .environment(terminalManager)
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
        .appUpdateRestartAlert(updateManager: appUpdateManager)
        .background {
            AppWindowModalOverlayPresenter(
                modal: rootWindowModal,
                onDismiss: dismissRootWindowModal
            )
            .frame(width: 0, height: 0)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                PrimaryToolbarButtonGroup(
                    selectedThreadID: selectedThreadID,
                    projectActions: toolbarProjectActions,
                    projectActionsThreadID: toolbarProjectActionsThreadID,
                    terminalTitle: terminalToggleTitle,
                    terminalDisplayState: terminalToolbarDisplayState,
                    terminalHelpText: "\(terminalToggleTitle) (\(KeyboardShortcut.toggleTerminalPane.displayString))",
                    diffDisplayState: diffViewerToolbarDisplayState,
                    diffHelpText: diffViewerToggleHelpText
                        + " (\(KeyboardShortcut.toggleDiffViewer.displayString))",
                    diffAccessibilityLabel: appState.isRightPaneVisible ? "Hide Diff Viewer" : "Show Diff Viewer",
                    diffAccessibilityValue: diffViewerToggleAccessibilityValue,
                    settingsBadgeState: appUpdateManager.toolbarBadgeState,
                    onProjectAction: { threadID, action in
                        runProjectAction(threadID: threadID, action: action)
                    },
                    onToggleTerminal: toggleTerminalPane,
                    onToggleDiffViewer: {
                        appState.toggleRightPane()
                    },
                    onOpenSettings: {
                        appState.openSettings(targetPage: appUpdateManager.toolbarBadgeState.settingsTargetPage)
                    }
                )
            }
            .sharedBackgroundVisibility(.hidden)
        }
        .onChange(of: appState.isLeftPaneVisible) { _, isVisible in
            splitVisibility = isVisible ? .all : .detailOnly
        }
        .onChange(of: splitVisibility) { _, visibility in
            appState.setLeftPaneVisible(visibility != .detailOnly)
        }
        .onChange(of: appState.selectedSidebarItem) { _, selection in
            updateDiffViewer(item: selection)
            cancelPendingCommitMessageGenerationIfNeeded()
        }
        .onChange(of: appState.previousSelection) { _, _ in
            guard appState.selectedSidebarItem == .settings else {
                return
            }
            updateDiffViewer(item: .settings)
        }
        .onChange(of: appState.isRightPaneVisible) { _, isVisible in
            diffViewModel.setWatchingEnabled(isVisible)
            // Hiding keeps the loaded workspace so toolbar stats stay visible;
            // showing upgrades a stats-only workspace to the full pane payload.
            if isVisible {
                updateDiffViewer(item: appState.selectedSidebarItem)
            }
        }
        .onChange(of: appState.pendingCommand) { _, command in
            handlePendingCommand(command)
        }
        .onChange(of: notificationRouter.pendingConversationId) { _, newValue in
            guard let newValue else { return }
            openConversation(with: newValue)
            notificationRouter.clearPendingIfMatches(newValue)
        }
        .onChange(of: terminalManager.runningProjectActionSessionIDs, initial: true) { _, runningSessionIDs in
            handleTerminalRunningSessionIDsChange(runningSessionIDs)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            onboardingViewModel.handleAppDidBecomeActive()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
            terminalManager.terminateAllSessions()
        }
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
        .preferredColorScheme(colorScheme(for: settingsViewModel.theme))
        .task(id: selectedThreadID) {
            await refreshToolbarProjectActions()
        }
        .onAppear {
            wireNotificationManager()
            startThreadActivityBackfillIfNeeded()
            restoreLastOpenThreadSelectionIfNeeded()
            updateDiffViewer(item: appState.selectedSidebarItem)
            diffViewModel.setWatchingEnabled(appState.isRightPaneVisible)
            if let pending = notificationRouter.pendingConversationId {
                openConversation(with: pending)
                notificationRouter.clearPendingIfMatches(pending)
            }
            // Mark-read of the active conversation is handled by `ThreadDetailView` once
            // the restored selection mounts; just sync the dock badge on launch.
            notificationManager.refreshBadgeCount()
        }
        // Publish the terminal-toggle action so the ⇧⌘T menu item in
        // `AlvearyApp.commands` runs the same default-shell-then-flip sequence
        // as the toolbar button — `terminalManager` is view-local `@State`, so
        // the menu needs a `FocusedValue` hop to reach it.
        .focusedSceneValue(\.toggleTerminalPaneAction, toggleTerminalPane)
    }

}

private extension ContentView {
    var selectedThreadID: PersistentIdentifier? {
        guard case .thread(let thread) = appState.selectedSidebarItem else {
            return nil
        }

        return thread.persistentModelID
    }

    var visibleThreadID: PersistentIdentifier? {
        selectedThreadID
    }

    var terminalToggleTitle: String {
        appState.isTerminalPaneVisible ? "Hide Terminal" : "Show Terminal"
    }

    func colorScheme(for theme: String) -> ColorScheme? {
        switch theme {
        case "light": .light
        case "dark": .dark
        default: nil
        }
    }

    func toggleTerminalPane() {
        if appState.isTerminalPaneVisible {
            appState.hideTerminalPane()
        } else {
            ensureDefaultShellSession(focus: true)
            appState.showTerminalPane()
        }
    }

    func handleTerminalRunningSessionIDsChange(_ runningSessionIDs: Set<UUID>) {
        let liveSessionIDs = Set(terminalManager.sessions.map(\.id))
        terminalToolbarTrackedSessionIDs.formIntersection(liveSessionIDs)

        if !runningSessionIDs.isEmpty {
            terminalToolbarResetTask?.cancel()
            terminalToolbarResetTask = nil
            terminalToolbarTrackedSessionIDs.formUnion(runningSessionIDs)
            terminalToolbarDisplayState = .running
            return
        }

        guard !terminalToolbarTrackedSessionIDs.isEmpty else {
            terminalToolbarDisplayState = .idle
            return
        }

        let completedSessionIDs = terminalToolbarTrackedSessionIDs
        terminalToolbarTrackedSessionIDs = []

        guard let outcome = TerminalToolbarCompletionOutcome.outcome(
            completedSessionIDs: completedSessionIDs,
            terminalManager: terminalManager
        ) else {
            terminalToolbarDisplayState = .idle
            return
        }

        terminalToolbarDisplayState = .completed(outcome)
        scheduleTerminalToolbarReset()
    }

    func scheduleTerminalToolbarReset() {
        terminalToolbarResetTask?.cancel()
        terminalToolbarResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            terminalToolbarDisplayState = .idle
            terminalToolbarResetTask = nil
        }
    }

    func canViewThread(_ id: PersistentIdentifier) -> Bool {
        guard visibleThreadID != id,
              let thread = uiModelContext.resolveThread(id: id) else {
            return false
        }

        return thread.archivedAt == nil
    }

    func viewThread(_ id: PersistentIdentifier) {
        guard let thread = uiModelContext.resolveThread(id: id),
              thread.archivedAt == nil else {
            return
        }

        appState.selectedSidebarItem = .thread(thread)
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
