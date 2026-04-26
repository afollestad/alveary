import AppKit
import Knit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) var uiModelContext

    let settingsService: SettingsService
    let shellRunner: ShellRunner
    private let gitHubCLI: GitHubCLIService
    private let providerDetection: any ProviderDetectionService
    private let agentRegistry: AgentRegistry
    private let providerRegistry: ProviderRegistry
    private let skillsService: SkillsService
    private let mcpService: MCPService
    private let agentsManager: any AgentsManager
    private let runtimeStore: any ConversationRuntimeStore
    private let worktreeManager: WorktreeManager
    private let providerSetup: ProviderSetupService
    private let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let notificationRouter: NotificationRouter

    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State var isAddProjectSheetPresented = false
    @State var pendingDiskImportAfterDismiss = false
    @State private var viewModelContext: ModelContext
    @State var sidebarViewModel: SidebarViewModel
    @State var diffViewModel: DiffViewerViewModel
    @State private var diffViewerWidth: CGFloat
    @State private var diffViewerTopSectionFraction: CGFloat
    @State private var terminalPaneHeight: CGFloat
    @State private var skillsViewModel: SkillsViewModel
    @State private var mcpViewModel: MCPViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State var terminalManager: TerminalManager
    @State private var toolbarProjectActions: [AlvearyProjectConfig.ProjectAction]
    @State var didAttemptLaunchSelectionRestore = false

    init(resolver: Resolver, appState: AppState) {
        self.init(dependencies: ContentViewDependencies.resolve(resolver), appState: appState)
    }

    init(dependencies: ContentViewDependencies, appState: AppState) {
        self.appState = appState
        self.settingsService = dependencies.settingsService
        self.shellRunner = dependencies.shellRunner
        self.gitHubCLI = dependencies.gitHubCLI
        self.providerDetection = dependencies.providerDetection
        self.agentRegistry = dependencies.agentRegistry
        self.providerRegistry = dependencies.providerRegistry
        self.skillsService = dependencies.skillsService
        self.mcpService = dependencies.mcpService
        self.agentsManager = dependencies.agentsManager
        self.runtimeStore = dependencies.runtimeStore
        self.worktreeManager = dependencies.worktreeManager
        self.providerSetup = dependencies.providerSetup
        self.fileListManager = dependencies.fileListManager
        self.notificationManager = dependencies.notificationManager
        self.notificationRouter = dependencies.notificationRouter
        let settings = dependencies.settingsService.current
        // Keep UI mutations on the container's main context so sidebar `@Query` reads
        // and imperative view-model saves stay in sync without requiring a relaunch.
        _viewModelContext = State(initialValue: dependencies.modelContainer.mainContext)
        _diffViewerWidth = State(initialValue: CGFloat(settings.diffViewerWidth))
        _diffViewerTopSectionFraction = State(initialValue: CGFloat(settings.diffViewerTopSectionFraction))
        _terminalPaneHeight = State(initialValue: CGFloat(settings.terminalPaneHeight))
        _sidebarViewModel = State(initialValue: Self.makeSidebarViewModel(dependencies: dependencies))
        _diffViewModel = State(initialValue: Self.makeDiffViewModel(dependencies: dependencies))
        _skillsViewModel = State(initialValue: SkillsViewModel(skillsService: dependencies.skillsService))
        _mcpViewModel = State(initialValue: MCPViewModel(mcpService: dependencies.mcpService))
        _settingsViewModel = State(initialValue: Self.makeSettingsViewModel(dependencies: dependencies))
        _terminalManager = State(initialValue: TerminalManager())
        _toolbarProjectActions = State(initialValue: [])
    }

    private static func makeSidebarViewModel(dependencies: ContentViewDependencies) -> SidebarViewModel {
        SidebarViewModel(
            agentsManager: dependencies.agentsManager,
            modelContext: dependencies.modelContainer.mainContext,
            shell: dependencies.shellRunner,
            gitHubCLI: dependencies.gitHubCLI,
            worktreeManager: dependencies.worktreeManager,
            settingsService: dependencies.settingsService,
            notificationManager: dependencies.notificationManager
        )
    }

    private static func makeDiffViewModel(dependencies: ContentViewDependencies) -> DiffViewerViewModel {
        DiffViewerViewModel(
            gitService: dependencies.gitService,
            gitHubService: dependencies.gitHubService,
            fileListManager: dependencies.fileListManager,
            agentsManager: dependencies.agentsManager
        )
    }

    private static func makeSettingsViewModel(dependencies: ContentViewDependencies) -> SettingsViewModel {
        let soundPreviewer = SettingsSoundPreviewer()
        return SettingsViewModel(
            settingsService: dependencies.settingsService,
            providerDetection: dependencies.providerDetection,
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
            settingsService: settingsService,
            providerRegistry: providerRegistry,
            worktreeManager: worktreeManager,
            providerSetup: providerSetup,
            fileListManager: fileListManager,
            notificationManager: notificationManager,
            loadInstalledSkills: { [skillsService] in
                (try? await skillsService.loadInstalled()) ?? []
            },
            diffViewModel: diffViewModel,
            skillsViewModel: skillsViewModel,
            mcpViewModel: mcpViewModel,
            settingsViewModel: settingsViewModel
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
                                areAgentActionsEnabled: activeDiffActionTarget() != nil,
                                topSectionFraction: $diffViewerTopSectionFraction,
                                onTopSectionFractionCommit: persistDiffViewerTopSectionFraction,
                                onCommitRequested: requestAgentCommit,
                                onOpenPRRequested: requestAgentOpenPR
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
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if let thread = selectedThread,
                   !toolbarProjectActions.isEmpty {
                    ForEach(Array(toolbarProjectActions.enumerated()), id: \.offset) { _, action in
                        Button {
                            runProjectAction(thread: thread, action: action)
                        } label: {
                            Label(action.name, systemImage: action.icon ?? "terminal")
                        }
                        .help(action.name)
                    }
                }

                Button(action: toggleTerminalPane) {
                    Label(
                        appState.isTerminalPaneVisible ? "Hide Terminal" : "Show Terminal",
                        systemImage: "terminal"
                    )
                }
                .help(
                    (appState.isTerminalPaneVisible ? "Hide Terminal" : "Show Terminal")
                        + " (\(KeyboardShortcut.toggleTerminalPane.displayString))"
                )

                DiffViewerToolbarButton(
                    diffStats: diffViewModel.diffStats,
                    action: {
                        appState.toggleRightPane()
                    }
                )
                .help(
                    diffViewerToggleHelpText
                        + " (\(KeyboardShortcut.toggleDiffViewer.displayString))"
                )
                .accessibilityLabel(appState.isRightPaneVisible ? "Hide Diff Viewer" : "Show Diff Viewer")
                .accessibilityValue(diffViewerToggleAccessibilityValue)

                Button {
                    appState.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .help("Open Settings (\(KeyboardShortcut.settings.displayString))")
            }
        }
        .onChange(of: appState.isLeftPaneVisible) { _, isVisible in
            splitVisibility = isVisible ? .all : .detailOnly
        }
        .onChange(of: splitVisibility) { _, visibility in
            appState.setLeftPaneVisible(visibility != .detailOnly)
        }
        .onChange(of: appState.selectedSidebarItem) { _, selection in
            updateDiffViewer(item: selection)
            cancelPendingDiffActionIfNeeded()
            persistLastOpenThreadSelection(for: selection)
        }
        .onChange(of: appState.previousSelection) { _, _ in
            guard appState.selectedSidebarItem == .settings else {
                return
            }
            updateDiffViewer(item: .settings)
        }
        .onChange(of: appState.isRightPaneVisible) { _, isVisible in
            diffViewModel.setWatchingEnabled(isVisible)
        }
        .onChange(of: appState.pendingCommand) { _, command in
            handlePendingCommand(command)
        }
        .onChange(of: appState.selectedConversationIDs) { _, _ in
            persistLastOpenThreadSelection(for: appState.selectedSidebarItem)
        }
        .onChange(of: activeConversationId) { _, newValue in
            guard let newValue else { return }
            notificationManager.markConversationRead(conversationId: newValue)
        }
        .onChange(of: notificationRouter.pendingConversationId) { _, newValue in
            guard let newValue else { return }
            openConversation(with: newValue)
            notificationRouter.clearPendingIfMatches(newValue)
        }
        .sheet(
            isPresented: $isAddProjectSheetPresented,
            // Wait for the sheet's dismissal to finish before opening the
            // `NSOpenPanel`, otherwise the modal pops on top of the still-animating
            // sheet and stutters the UI.
            onDismiss: handleAddProjectSheetDismiss,
            content: addProjectSheetContent
        )
        .preferredColorScheme(colorScheme(for: settingsViewModel.theme))
        .task(id: selectedThread?.project?.path) {
            await refreshToolbarProjectActions()
        }
        .onAppear {
            wireNotificationManager()
            restoreLastOpenThreadSelectionIfNeeded()
            updateDiffViewer(item: appState.selectedSidebarItem)
            diffViewModel.setWatchingEnabled(appState.isRightPaneVisible)
            if let pending = notificationRouter.pendingConversationId {
                openConversation(with: pending)
                notificationRouter.clearPendingIfMatches(pending)
            }
            // Mark-read of the active conversation is handled by the `onChange(of: activeConversationId)`
            // observer once the restored selection propagates; just sync the dock badge on launch.
            notificationManager.refreshBadgeCount()
        }
        // Publish the terminal-toggle action so the ⇧⌘T menu item in
        // `AlvearyApp.commands` runs the same `ensureSelection()`-then-flip
        // sequence as the toolbar button — `terminalManager` is view-local
        // `@State`, so the menu needs a `FocusedValue` hop to reach it.
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

    var selectedThread: AgentThread? {
        guard let selectedThreadID else {
            return nil
        }

        return uiModelContext.resolveThread(id: selectedThreadID)
    }

    var visibleThreadID: PersistentIdentifier? {
        selectedThreadID
    }

    var activeConversationId: String? {
        guard let selectedThread else {
            return nil
        }
        return selectedConversation(in: selectedThread, modelContext: uiModelContext, appState: appState)?.id
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
            terminalManager.ensureSelection()
            appState.showTerminalPane()
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
        guard let thread = selectedThread,
              let projectPath = thread.project?.path else {
            toolbarProjectActions = []
            return
        }

        let config = await AlvearyProjectConfig(projectPath: projectPath)

        guard selectedThread?.persistentModelID == thread.persistentModelID else {
            return
        }

        toolbarProjectActions = config.actions ?? []
    }

    var diffViewerToggleHelpText: String {
        let action = appState.isRightPaneVisible ? "Hide Diff Viewer" : "Show Diff Viewer"
        let stats = diffViewModel.diffStats

        guard !stats.isEmpty else {
            return action
        }

        return "\(action), +\(stats.additions) -\(stats.deletions)"
    }

    var diffViewerToggleAccessibilityValue: String {
        let stats = diffViewModel.diffStats
        guard !stats.isEmpty else {
            return ""
        }

        return "\(stats.additions) additions, \(stats.deletions) deletions"
    }

    func effectiveDiffViewerWidth(availableWidth: CGFloat) -> CGFloat {
        ContentDiffViewerWidthPolicy.effectiveWidth(storedWidth: diffViewerWidth, availableWidth: availableWidth)
    }

    func effectiveDiffViewerBounds(availableWidth: CGFloat) -> ClosedRange<Double> {
        ContentDiffViewerWidthPolicy.bounds(availableWidth: availableWidth)
    }
}

@MainActor
private final class SettingsSoundPreviewer {
    private var currentSound: NSSound?

    func play(_ soundName: String) {
        currentSound?.stop()
        let sound = NSSound(named: NSSound.Name(soundName))
        currentSound = sound
        sound?.play()
    }
}
