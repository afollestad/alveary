import AppKit
import Knit
import SwiftData
import SwiftUI

struct ContentView: View {
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var uiModelContext

    private let settingsService: SettingsService
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

    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var viewModelContext: ModelContext
    @State private var sidebarViewModel: SidebarViewModel
    @State private var diffViewModel: DiffViewerViewModel
    @State private var diffViewerWidth: CGFloat
    @State private var diffViewerTopSectionFraction: CGFloat
    @State private var terminalPaneHeight: CGFloat
    @State private var skillsViewModel: SkillsViewModel
    @State private var mcpViewModel: MCPViewModel
    @State private var settingsViewModel: SettingsViewModel
    @State private var terminalManager: TerminalManager

    init(resolver: Resolver, appState: AppState) {
        self.appState = appState
        let settingsService = resolver.settingsService()
        let gitHubCLI = resolver.gitHubCLIService()
        let providerDetection = resolver.providerDetectionService()
        let agentRegistry = resolver.agentRegistry()
        let providerRegistry = resolver.providerRegistry()
        let skillsService = resolver.skillsService()
        let mcpService = resolver.mcpService()
        let agentsManager = resolver.agentsManager()
        let runtimeStore = resolver.conversationRuntimeStore()
        let worktreeManager = resolver.worktreeManager()
        let providerSetup = resolver.providerSetupService(); let fileListManager = resolver.fileListManager()

        self.settingsService = settingsService
        self.gitHubCLI = gitHubCLI
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
        self.providerRegistry = providerRegistry
        self.skillsService = skillsService
        self.mcpService = mcpService
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.fileListManager = fileListManager

        let viewModelContext = resolver.modelContext(); _viewModelContext = State(initialValue: viewModelContext)
        _diffViewerWidth = State(initialValue: CGFloat(settingsService.current.diffViewerWidth))
        _diffViewerTopSectionFraction = State(initialValue: CGFloat(settingsService.current.diffViewerTopSectionFraction))
        _terminalPaneHeight = State(initialValue: CGFloat(settingsService.current.terminalPaneHeight))
        _sidebarViewModel = State(initialValue: SidebarViewModel(
            agentsManager: agentsManager,
            modelContext: viewModelContext,
            shell: resolver.shellRunner(),
            gitHubCLI: gitHubCLI,
            worktreeManager: worktreeManager,
            settingsService: settingsService
        ))
        _diffViewModel = State(initialValue: DiffViewerViewModel(
            gitService: resolver.gitService(),
            gitHubService: resolver.gitHubService(),
            fileListManager: fileListManager,
            agentsManager: agentsManager
        ))
        _skillsViewModel = State(initialValue: SkillsViewModel(skillsService: skillsService))
        _mcpViewModel = State(initialValue: MCPViewModel(mcpService: mcpService))
        _settingsViewModel = State(initialValue: SettingsViewModel(
            settingsService: settingsService,
            providerDetection: providerDetection,
            agentRegistry: agentRegistry
        ))
        _terminalManager = State(initialValue: TerminalManager())
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
            loadInstalledSkills: {
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
                HStack(spacing: 0) {
                    middlePane
                        .frame(maxWidth: .infinity)

                    if appState.isRightPaneVisible {
                        ContentDiffViewerResizeHandle(
                            width: $diffViewerWidth,
                            bounds: AppSettings.supportedDiffViewerWidthRange,
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
                        .frame(width: diffViewerWidth)
                    }
                }

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
                Button {
                    appState.isLeftPaneVisible.toggle()
                } label: {
                    Label(
                        appState.isLeftPaneVisible ? "Hide Sidebar" : "Show Sidebar",
                        systemImage: "sidebar.leading"
                    )
                }
                .keyboardShortcut("\\", modifiers: .command)

                Button {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        appState.isRightPaneVisible.toggle()
                    }
                } label: {
                    Label(
                        appState.isRightPaneVisible ? "Hide Diff Viewer" : "Show Diff Viewer",
                        systemImage: "sidebar.trailing"
                    )
                }
                .keyboardShortcut("\\", modifiers: [.command, .shift])

                Button(action: toggleTerminalPane) {
                    Label(
                        appState.isTerminalPaneVisible ? "Hide Terminal" : "Show Terminal",
                        systemImage: "terminal"
                    )
                }

                Button {
                    appState.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: appState.isLeftPaneVisible) { _, isVisible in
            splitVisibility = isVisible ? .all : .detailOnly
        }
        .onChange(of: splitVisibility) { _, visibility in
            appState.isLeftPaneVisible = visibility != .detailOnly
        }
        .onChange(of: appState.selectedSidebarItem) { _, selection in
            updateDiffViewer(item: selection)
            cancelPendingDiffActionIfNeeded()
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
        .preferredColorScheme(colorScheme(for: settingsViewModel.theme))
        .onAppear {
            updateDiffViewer(item: appState.selectedSidebarItem)
            diffViewModel.setWatchingEnabled(appState.isRightPaneVisible)
        }
    }
}

private extension ContentView {
    var visibleThreadID: PersistentIdentifier? {
        if case .thread(let thread) = appState.selectedSidebarItem {
            return thread.persistentModelID
        }

        return nil
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
              let thread = resolveThread(id: id) else {
            return false
        }

        return thread.archivedAt == nil
    }

    func viewThread(_ id: PersistentIdentifier) {
        guard let thread = resolveThread(id: id),
              thread.archivedAt == nil else {
            return
        }

        appState.selectedSidebarItem = .thread(thread)
    }

    func updateDiffViewer(item: SidebarItem?) {
        let thread: AgentThread?

        switch item {
        case .thread(let selectedThread):
            thread = selectedThread
        case .settings:
            if case .threadId(let id) = appState.previousSelection,
               let preservedThread = uiModelContext.model(for: id) as? AgentThread,
               preservedThread.archivedAt == nil {
                thread = preservedThread
            } else {
                thread = nil
            }
        default:
            thread = nil
        }

        guard let thread,
              let path = thread.worktreePath ?? thread.project?.path else {
            diffViewModel.clear()
            return
        }

        let baseRef = thread.project?.baseRef ?? "main"
        let remoteName = thread.project?.remoteName
        let conversationIds = Set(thread.conversations.map(\.id))

        Task {
            await diffViewModel.switchToDirectory(
                path,
                baseRef: baseRef,
                remoteName: remoteName,
                conversationIds: conversationIds
            )
        }
    }

    func handlePendingCommand(_ command: AppState.CommandRequest?) {
        guard let command else {
            return
        }

        let commandID = command.id
        Task { @MainActor in
            defer {
                if appState.pendingCommand?.id == commandID {
                    appState.pendingCommand = nil
                }
            }

            do {
                switch command {
                case .newProject:
                    let panel = NSOpenPanel()
                    panel.canChooseDirectories = true
                    panel.canChooseFiles = false
                    panel.allowsMultipleSelection = false

                    guard panel.runModal() == .OK,
                          let url = panel.url else {
                        return
                    }

                    let createdProject = try await sidebarViewModel.createProject(path: url.path)
                    guard appState.pendingCommand?.id == commandID else {
                        return
                    }

                    appState.selectedSidebarItem = resolveProject(path: createdProject.path).map(SidebarItem.project)

                case .newThread:
                    guard let project = currentProjectContext() else {
                        return
                    }

                    let createdThread = try await sidebarViewModel.createThread(
                        project: project,
                        provider: settingsService.current.defaultProvider,
                        permissionMode: settingsService.current.permissionMode
                    )
                    guard appState.pendingCommand?.id == commandID else {
                        return
                    }

                    appState.selectedSidebarItem = resolveThread(id: createdThread.persistentModelID).map(SidebarItem.thread)
                }
            } catch {
                guard appState.pendingCommand?.id == commandID else {
                    return
                }
                sidebarViewModel.presentSidebarError(error)
            }
        }
    }

    func activeDiffActionTarget() -> (thread: AgentThread, conversation: Conversation)? {
        guard case .thread(let thread) = appState.selectedSidebarItem,
              let conversation = appState.selectedConversation(in: thread) else {
            return nil
        }

        return (thread, conversation)
    }

    func requestAgentCommit() {
        guard let (_, conversation) = activeDiffActionTarget() else {
            return
        }

        let message: String
        if diffViewModel.files.contains(where: { $0.isStaged }) {
            message = "Please review the currently staged changes in this worktree and create an appropriate git commit for them."
        } else {
            message = "Please review the current uncommitted changes in this worktree and create an appropriate git commit."
        }

        appState.requestDiffAction(message: message, conversationID: conversation.persistentModelID)
    }

    func requestAgentOpenPR() {
        guard let (thread, conversation) = activeDiffActionTarget() else {
            return
        }

        let baseRef = thread.project?.baseRef ?? "main"
        let message = "Please push or publish the current branch if needed, then open a pull request against `\(baseRef)` and share the PR URL."
        appState.requestDiffAction(message: message, conversationID: conversation.persistentModelID)
    }

    func cancelPendingDiffActionIfNeeded() {
        guard let request = appState.pendingDiffAction else {
            return
        }

        guard let activeConversationID = activeDiffActionTarget()?.conversation.persistentModelID,
              activeConversationID == request.conversationID else {
            appState.pendingDiffAction = nil
            return
        }
    }

    func currentProjectContext() -> Project? {
        switch appState.selectedSidebarItem {
        case .project(let project):
            return project
        case .thread(let thread):
            return thread.project
        case .settings:
            guard let bookmark = appState.previousSelection else {
                return nil
            }

            switch bookmark {
            case .projectPath(let path):
                return resolveProject(path: path)
            case .threadId(let id):
                return resolveThread(id: id)?.project
            case .skills, .mcp:
                return nil
            }
        default:
            return nil
        }
    }

    func resolveProject(path: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == path
        })
        return try? uiModelContext.fetch(descriptor).first
    }

    func resolveThread(id: PersistentIdentifier) -> AgentThread? {
        uiModelContext.model(for: id) as? AgentThread
    }

    func persistDiffViewerWidth(_ width: CGFloat) {
        settingsService.update {
            $0.diffViewerWidth = width
        }
    }

    func persistDiffViewerTopSectionFraction(_ fraction: CGFloat) {
        settingsService.update {
            $0.diffViewerTopSectionFraction = fraction
        }
    }

    func persistTerminalPaneHeight(_ height: CGFloat) {
        settingsService.update {
            $0.terminalPaneHeight = height
        }
    }
}
