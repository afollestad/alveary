# Part 4a: Layout

App entry point, NavigationSplitView, sidebar, middle pane, right pane, visual design. Depends on Parts 1-3.

## App Layout

### App Entry Point

The root `SkepApp` and `ContentView` wire the resolver to all view models and establish the panel layout. Build this after all view models and services from Parts 1-3 are implemented. The minimal `AppDelegate` shell already exists from the Phase 1 bootstrap stub, so this phase only replaces the placeholder scene body while continuing to wire `@NSApplicationDelegateAdaptor`; Part 4e fills in the delegate's lifecycle logic later.

**Layout approach (validated)**: a **two-column `NavigationSplitView`** (sidebar + detail) where the detail pane internally splits into chat + diff viewer via `HStack` with conditional rendering. The sidebar still uses the native two-column show/hide behavior; only the right diff pane uses a custom split. This pattern was chosen because:
- `NavigationSplitView`'s native three-column mode does not support programmatic detail pane toggling on macOS 26 (`NavigationSplitViewVisibility` binding changes have no effect).
- `HSplitView` works but produces incorrect animation direction (middle pane slides right instead of diff pane pushing in from the right).
- `HStack` + `withAnimation` + `.clipped()` gives correct push-from-right animation for the diff viewer toggle.

Composition-root lifetime matters here. The shared assembler is app-lifetime and `@MainActor` because `ScopedModuleAssembler` is not `Sendable`; `ContentView` then owns the long-lived sidebar/diff/settings-style view models in `@State`. Resolve the transient write `ModelContext` once at that same boundary and pass it downward explicitly instead of calling `resolver.modelContext()` from `body`. Likewise, resolve container-scoped services once in `ContentView.init` and keep them as plain stored properties; do not forward `Resolver` deeper into `MiddlePane` or the chat subtree after composition.

```swift
/// Shared app-lifetime DI container.
@MainActor
private let appAssembler = ScopedModuleAssembler<Resolver>([
    DataAssembly(),
    ShellAssembly(), SettingsAssembly(), DetectionAssembly(),
    AgentAssembly(), SessionAssembly(),
    GitAssembly(), GitHubAssembly(),
    SkillsAssembly(), MCPAssembly()
])

@main
struct SkepApp: App {  // Skep/App/SkepApp.swift
    let resolver = appAssembler.resolver
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @State private var appState = AppState()

    var body: some Scene {
        Window("Skep", id: "main") {
            ContentView(resolver: resolver, appState: appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Thread") { appState.startNewThreadFlow() }
                    .keyboardShortcut("n", modifiers: .command)
                Button("New Project...") { appState.openNewProjectFlow() }
                    .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .appSettings) {
                Button("Settings...") { appState.openSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
        }
        .modelContainer(resolver.modelContainer())
    }
}

struct ContentView: View {  // Skep/App/ContentView.swift
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var uiModelContext
    private let settingsService: SettingsService
    private let gitHubCLI: GitHubCLIService
    private let providerDetection: any ProviderDetectionService
    private let agentRegistry: AgentRegistry
    private let agentsManager: any AgentsManager
    private let runtimeStore: any ConversationRuntimeStore
    private let providerRegistry: ProviderRegistry
    private let worktreeManager: WorktreeManager
    private let providerSetup: ProviderSetupService
    private let fileListManager: FileListManager
    private let skillsService: SkillsService
    private let mcpService: MCPService
    @State private var splitVisibility: NavigationSplitViewVisibility = .all
    @State private var viewModelContext: ModelContext
    @State private var sidebarVM: SidebarViewModel
    @State private var diffVM: DiffViewerViewModel
    // Lazy app-lifetime screen VMs.
    @State private var skillsVM: SkillsViewModel?
    @State private var mcpVM: MCPViewModel?
    @State private var settingsVM: SettingsViewModel?

    init(resolver: Resolver, appState: AppState) {
        self.appState = appState
        let settingsService = resolver.settingsService()
        let gitHubCLI = resolver.gitHubCLIService()
        let providerDetection = resolver.providerDetectionService()
        let agentRegistry = resolver.agentRegistry()
        let agentsManager = resolver.agentsManager()
        let runtimeStore = resolver.conversationRuntimeStore()
        let providerRegistry = resolver.providerRegistry()
        let worktreeManager = resolver.worktreeManager()
        let providerSetup = resolver.providerSetupService()
        let fileListManager = resolver.fileListManager()
        let skillsService = resolver.skillsService()
        let mcpService = resolver.mcpService()
        self.settingsService = settingsService
        self.gitHubCLI = gitHubCLI
        self.providerDetection = providerDetection
        self.agentRegistry = agentRegistry
        self.agentsManager = agentsManager
        self.runtimeStore = runtimeStore
        self.providerRegistry = providerRegistry
        self.worktreeManager = worktreeManager
        self.providerSetup = providerSetup
        self.fileListManager = fileListManager
        self.skillsService = skillsService
        self.mcpService = mcpService
        let viewModelContext = resolver.modelContext()
        self._viewModelContext = State(initialValue: viewModelContext)
        self._sidebarVM = State(initialValue: SidebarViewModel(
            agentsManager: agentsManager,
            modelContext: viewModelContext,
            shell: resolver.shellRunner(),
            gitHubCLI: gitHubCLI,
            worktreeManager: worktreeManager,
            settingsService: settingsService
        ))
        self._diffVM = State(initialValue: DiffViewerViewModel(
            gitService: resolver.gitService(),
            gitHubService: resolver.gitHubService(),
            fileListManager: fileListManager,
            agentsManager: agentsManager
        ))
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $splitVisibility) {
            SidebarView(viewModel: sidebarVM, appState: appState)
        } detail: {
            // `HStack` gives the validated push-from-right diff-pane toggle.
            HStack(spacing: 0) {
                MiddlePane(
                    appState: appState,
                    modelContext: viewModelContext,
                    gitHubCLI: gitHubCLI,
                    providerDetection: providerDetection,
                    agentRegistry: agentRegistry,
                    agentsManager: agentsManager,
                    runtimeStore: runtimeStore,
                    settingsService: settingsService,
                    providerRegistry: providerRegistry,
                    worktreeManager: worktreeManager,
                    providerSetup: providerSetup,
                    fileListManager: fileListManager,
                    skillsService: skillsService,
                    mcpService: mcpService,
                    loadInstalledSkills: { await skillsService.loadInstalled() },
                    diffVM: diffVM,
                    skillsVM: $skillsVM,
                    mcpVM: $mcpVM,
                    settingsVM: $settingsVM
                )
                .frame(maxWidth: .infinity)

                if appState.isRightPaneVisible {
                    Divider()
                    DiffViewerPane(
                        viewModel: diffVM,
                        areAgentActionsEnabled: activeDiffActionTarget() != nil,
                        onCommitRequested: { requestAgentCommit() },
                        onOpenPRRequested: { requestAgentOpenPR() }
                    )
                        .frame(minWidth: 250, idealWidth: 350, maxWidth: 500)
                }
            }
            .clipped()
        }
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

                Button {
                    appState.openSettings()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
            }
        }
        .onChange(of: appState.isLeftPaneVisible) { _, visible in
            splitVisibility = visible ? .all : .detailOnly
        }
        .onChange(of: splitVisibility) { _, visibility in
            appState.isLeftPaneVisible = visibility != .detailOnly
        }
        .onChange(of: appState.selectedSidebarItem) { _, newItem in
            cancelPendingDiffActionIfNeeded(for: newItem)
            updateDiffViewer(item: newItem)
        }
        .onChange(of: appState.previousSelection) { _, _ in
            guard appState.selectedSidebarItem == .settings else { return }
            updateDiffViewer(item: .settings)
        }
        .onChange(of: appState.isRightPaneVisible) { _, visible in
            diffVM.setWatchingEnabled(visible)
        }
        .onChange(of: appState.pendingCommand) { _, command in
            handlePendingCommand(command)
        }
        .onAppear {
            updateDiffViewer(item: appState.selectedSidebarItem)
            diffVM.setWatchingEnabled(appState.isRightPaneVisible)
        }
    }

    private func updateDiffViewer(item: SidebarItem?) {
        let thread: AgentThread?
        switch item {
        case .thread(let selectedThread):
            thread = selectedThread
        case .settings:
            if case .threadId(let id) = appState.previousSelection,
               let preserved = uiModelContext.model(for: id) as? AgentThread,
               preserved.archivedAt == nil {
                thread = preserved
            } else {
                thread = nil
            }
        default:
            thread = nil
        }

        if let thread,
           let path = thread.worktreePath ?? thread.project?.path {
            let baseRef = thread.project?.baseRef ?? "main"
            let remoteName = thread.project?.remoteName
            let conversationIds = Set(thread.conversations.map(\.id))
            Task {
                await diffVM.switchToDirectory(
                    path,
                    baseRef: baseRef,
                    remoteName: remoteName,
                    conversationIds: conversationIds
                )
            }
        } else {
            diffVM.clear()
        }
    }

    private func cancelPendingDiffActionIfNeeded(for item: SidebarItem?) {
        guard let request = appState.pendingDiffAction else { return }
        guard case .thread(let thread) = item,
              let conversation = appState.selectedConversation(in: thread),
              conversation.persistentModelID == request.conversationID else {
            appState.pendingDiffAction = nil
            return
        }
    }

    private func handlePendingCommand(_ command: AppState.CommandRequest?) {
        guard let command else { return }
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
                    guard panel.runModal() == .OK, let url = panel.url else { return }
                    let createdProject = try await sidebarVM.createProject(path: url.path)
                    guard appState.pendingCommand?.id == commandID else { return }
                    appState.selectedSidebarItem = resolveProject(path: createdProject.path).map(SidebarItem.project)

                case .newThread:
                    guard let project = currentProjectContext() else { return }
                    let settings = settingsService.current
                    let createdThread = try await sidebarVM.createThread(
                        project: project,
                        provider: settings.defaultProvider,
                        permissionMode: settings.permissionMode
                    )
                    guard appState.pendingCommand?.id == commandID else { return }
                    appState.selectedSidebarItem = resolveThread(id: createdThread.persistentModelID).map(SidebarItem.thread)
                }
            } catch {
                guard appState.pendingCommand?.id == commandID else { return }
                sidebarVM.presentSidebarError(error)
            }
        }
    }

    private func activeDiffActionTarget() -> (thread: AgentThread, conversation: Conversation)? {
        guard case .thread(let thread) = appState.selectedSidebarItem,
              let conversation = appState.selectedConversation(in: thread) else {
            return nil
        }
        return (thread, conversation)
    }

    private func requestAgentCommit() {
        guard let (_, conversation) = activeDiffActionTarget() else {
            return
        }
        let hasStagedChanges = diffVM.files.contains(where: \.isStaged)
        let message: String
        if hasStagedChanges {
            message = "Please review the currently staged changes in this worktree and create an appropriate git commit for them."
        } else {
            message = "Please review the current uncommitted changes in this worktree and create an appropriate git commit."
        }
        appState.requestDiffAction(
            message: message,
            conversationID: conversation.persistentModelID
        )
    }

    private func requestAgentOpenPR() {
        guard let (thread, conversation) = activeDiffActionTarget() else {
            return
        }
        let baseRef = thread.project?.baseRef ?? "main"
        let message = "Please push or publish the current branch if needed, then open a pull request against `\(baseRef)` and share the PR URL."
        appState.requestDiffAction(
            message: message,
            conversationID: conversation.persistentModelID
        )
    }

    private func currentProjectContext() -> Project? {
        switch appState.selectedSidebarItem {
        case .project(let project):
            return project
        case .thread(let thread):
            return thread.project
        case .settings:
            // Reuse the preserved pre-settings bookmark for app-wide commands.
            guard let bookmark = appState.previousSelection else { return nil }
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

    private func resolveProject(path: String) -> Project? {
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.path == path })
        return try? uiModelContext.fetch(descriptor).first
    }

    private func resolveThread(id: PersistentIdentifier) -> AgentThread? {
        uiModelContext.model(for: id) as? AgentThread
    }
}
```

`ConversationViewModel` is still created per conversation in `ConversationView`, while `SkillsViewModel`, `MCPViewModel`, and `SettingsViewModel` stay lazily cached at the `ContentView` level. App-wide menu commands also route through this same composition root via `AppState.pendingCommand`, so Settings can reuse the preserved pre-settings bookmark instead of losing project/thread context. Keep the command handlers on the already-resolved `settingsService` / `SidebarViewModel` boundary rather than re-entering Knit from deeper helper methods.

### Visual Layout (Three Panels)

The app is **single-window**. Projects, threads, conversations, skills, MCP, and settings all live in one SwiftUI `Window` scene. The left pane holds navigation (Skills, MCP, projects, archived threads), the middle pane holds the active screen or chat, and the optional right pane shows repo changes plus contextual actions such as **Commit**, **Open PR**, or **View PR**.

### Chat View Detail (Middle Pane When Thread Selected)

**After agent completes a turn (idle):**
```
┌────────────────────────────────────────────┐
│  [Conv 1] [Conv 2]  ← conversation tabs    │
├────────────────────────────────────────────┤
│                                            │
│  ┌─ You ─────────────────────────────┐     │
│  │ Fix the auth bug in `login.ts`    │     │
│  └───────────────────────────────────┘     │
│                                            │
│  ┌─ Working ─────────────────────────┐     │
│  │ ▸ Used 3 tools, 1 file edit       │     │
│  │   (click to expand)               │     │
│  └───────────────────────────────────┘     │
│                                            │
│  ┌─ Claude ──────────────────────────┐     │
│  │ I've fixed the authentication     │     │
│  │ bug. The issue was in the         │     │
│  │ `validateToken()` function...     │     │
│  │                                   │     │
│  │ ```typescript                     │     │
│  │ function validateToken(token) {   │     │
│  │   // fixed implementation         │     │
│  │ }                          [Copy] │     │
│  │ ```                               │     │
│  └───────────────────────────────────┘     │
│                                            │
│  ╭────────────────────────────────────────╮ │
│  │ ● src/auth.ts                   [Diff]│ │
│  ├────────────────────────────────────────┤ │
│  │ ● src/login.ts                  [Diff]│ │
│  ├────────────────────────────────────────┤ │
│  │ + src/auth.test.ts              [Diff]│ │
│  ├────────────────────────────────────────┤ │
│  [Type a message...]              [Send ▸] │
└────────────────────────────────────────────┘
```

The **uncommitted changes list** sits above the input, driven by `DiffViewerViewModel.files`. Each row shows a status indicator (● modified, + new, − deleted, → renamed), file path (staged renames as `old → new`), and a [Diff] button that opens the right pane focused on that row. Auto-updates on thread switch, app activation, local git mutations, and agent idle transition. Cross-directory switches clear immediately. Hidden when no uncommitted changes exist.

**While agent is working (busy — tool use phase):**
```
┌────────────────────────────────────────────┐
│  [Conv 1] [Conv 2]  ← conversation tabs    │
├────────────────────────────────────────────┤
│                                            │
│  ┌─ You ─────────────────────────────┐     │
│  │ Fix the auth bug in `login.ts`    │     │
│  └───────────────────────────────────┘     │
│                                            │
│  ┌─ Claude is working... ────────────┐     │
│  │ ✓ Read `src/auth.ts`             │     │
│  │ ✓ Read `src/login.ts`            │     │
│  │ ● Editing `src/auth.ts`      4s  │     │
│  │                                   │     │
│  └───────────────────────────────────┘     │
│                                            │
│  ╭────────────────────────────────────────╮ │
│  │ Send a message to steer, or queue for │ │
│  │ next turn...          [Queue] [Stop ■]│ │
│  ╰────────────────────────────────────────╯ │
└────────────────────────────────────────────┘
```

**While agent is generating text (busy — streaming response):** the working block collapses to a summary and a `StreamingBubble` shows the assistant's in-progress response as plain text with a blinking cursor. Text appears progressively via `messageChunk` events. When the full `assistant` event arrives, the `StreamingBubble` is replaced by a markdown-rendered `AssistantBubble`. See the [Composer State and Live Progress supplement](supplement-composer-and-live-progress.md) for `StreamingBubble` implementation.

### Left Pane (Sidebar)

The left pane is the navigation hierarchy. Toggled via a menu bar button. Layout diagram and full sidebar interaction details are in [Part 4b: Sidebar](part4b-sidebar.md).

### Middle Pane (Content)

Shows whatever is selected in the left pane. Implemented as a `MiddlePane` view that switches content based on `appState.selectedSidebarItem`:

```swift
struct MiddlePane: View {  // Skep/App/MiddlePane.swift
    @Bindable var appState: AppState
    let modelContext: ModelContext
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    let agentRegistry: AgentRegistry
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let fileListManager: FileListManager
    let skillsService: SkillsService
    let mcpService: MCPService
    let loadInstalledSkills: () async -> [Skill]
    let diffVM: DiffViewerViewModel
    @Environment(\.modelContext) private var uiModelContext
    // Lazy-init bindings — created on first access, retained for the app's lifetime.
    // Passed in from ContentView's @State properties so they survive navigation.
    @Binding var skillsVM: SkillsViewModel?
    @Binding var mcpVM: MCPViewModel?
    @Binding var settingsVM: SettingsViewModel?
    @Query private var projects: [Project]

    var body: some View {
        switch appState.selectedSidebarItem {
        case .skills:
            SkillsScreen(viewModel: resolveSkillsVM())
        case .mcp:
            MCPScreen(viewModel: resolveMCPVM())
        case .project(let project):
            ProjectSettingsView(
                project: project,
                gitHubCLI: gitHubCLI,
                providerDetection: providerDetection,
                agentRegistry: agentRegistry
            )
                .id(project.path)
        case .thread(let thread):
            ThreadDetailView(
                thread: thread,
                appState: appState,
                modelContext: modelContext,
                agentsManager: agentsManager,
                runtimeStore: runtimeStore,
                settingsService: settingsService,
                providerRegistry: providerRegistry,
                worktreeManager: worktreeManager,
                providerSetup: providerSetup,
                fileListManager: fileListManager,
                // This injected loader is the fallback path before the conversation has
                // session-advertised slash commands. The chat subtree stays decoupled
                // from the DI container and `SkillsService` itself.
                loadSkillCompletions: loadInstalledSkills,
                diffViewModel: diffVM
            )
                .id(thread.persistentModelID)
        case .settings:
            SettingsScreen(viewModel: resolveSettingsVM()) {
                // Dismiss: resolve the lightweight bookmark back to a live SidebarItem.
                // Uses `modelContext` to fetch the model by its stable identifier,
                // falling back to the parent project (or nil → empty state) if the
                // bookmarked thread was archived/deleted while Settings was open.
                appState.selectedSidebarItem = appState.previousSelection
                    .flatMap { resolveSidebarBookmark($0) }
            }
        case nil:
            if projects.isEmpty {
                EmptyStateView(...)  // "Add your first project"
            } else {
                EmptyStateView(...)  // "Select a project or thread"
            }
        }
    }

    private func resolveSkillsVM() -> SkillsViewModel {
        if let vm = skillsVM { return vm }
        let vm = SkillsViewModel(skillsService: skillsService)
        skillsVM = vm
        return vm
    }

    private func resolveMCPVM() -> MCPViewModel {
        if let vm = mcpVM { return vm }
        let vm = MCPViewModel(mcpService: mcpService)
        mcpVM = vm
        return vm
    }

    private func resolveSettingsVM() -> SettingsViewModel {
        if let vm = settingsVM { return vm }
        let vm = SettingsViewModel(settingsService: settingsService)
        settingsVM = vm
        return vm
    }

    /// Resolve a lightweight bookmark back to a live SidebarItem. Archived thread
    /// bookmarks heal to their parent project so Settings dismiss never reopens an
    /// archived chat; deleted models fall back to nil (empty state).
    private func resolveSidebarBookmark(_ bookmark: AppState.SidebarBookmark) -> SidebarItem? {
        switch bookmark {
        case .skills: return .skills
        case .mcp: return .mcp
        case .projectPath(let path):
            let descriptor = FetchDescriptor<Project>(predicate: #Predicate { $0.path == path })
            guard let project = try? uiModelContext.fetch(descriptor).first else { return nil }
            return .project(project)
        case .threadId(let id):
            guard let thread = uiModelContext.model(for: id) as? AgentThread else { return nil }
            if thread.archivedAt != nil {
                return thread.project.map(SidebarItem.project)
            }
            return .thread(thread)
        }
    }
}

struct ThreadDetailView: View {  // Skep/Views/Chat/ThreadDetailView.swift
    let thread: AgentThread
    @Bindable var appState: AppState
    let modelContext: ModelContext
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let settingsService: SettingsService
    let providerRegistry: ProviderRegistry
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let fileListManager: FileListManager
    let loadSkillCompletions: () async -> [Skill]
    let diffViewModel: DiffViewerViewModel
    @Environment(\.modelContext) private var uiModelContext
    @State private var createConversationError: String?

    private var conversations: [Conversation] {
        thread.conversations.sorted { $0.displayOrder < $1.displayOrder }
    }

    private var selectedConversationID: PersistentIdentifier? {
        appState.selectedConversation(in: thread)?.persistentModelID
    }

    var body: some View {
        if let conversation = appState.selectedConversation(in: thread) {
            VStack(spacing: 0) {
                if let createConversationError {
                    InlineBanner(message: createConversationError, severity: .error) {
                        self.createConversationError = nil
                    }
                }
                ConversationTabs(
                    conversations: conversations,
                    selectedConversation: conversation,
                    statusForConversation: { agentsManager.status(for: $0.id) },
                    onSelect: { appState.selectConversation($0, in: thread) },
                    // ConversationTabs owns the + button and its Cmd+T shortcut.
                    onCreate: { Task { await createConversation() } }
                )
                ConversationView(
                    conversation: conversation,
                    agentsManager: agentsManager,
                    runtimeStore: runtimeStore,
                    modelContext: modelContext,
                    settingsService: settingsService,
                    providerRegistry: providerRegistry,
                    worktreeManager: worktreeManager,
                    providerSetup: providerSetup,
                    fileListManager: fileListManager,
                    loadSkillCompletions: loadSkillCompletions,
                    diffViewModel: diffViewModel,
                    appState: appState
                )
                    .id(conversation.id)
            }
            .task(id: thread.persistentModelID) {
                appState.repairSelectedConversationIfNeeded(for: thread)
            }
            .task(id: selectedConversationID) {
                cancelPendingDiffActionIfNeeded()
            }
        } else {
            EmptyStateView(...)  // "Create your first conversation"
                .task(id: thread.persistentModelID) {
                    appState.repairSelectedConversationIfNeeded(for: thread)
                }
                .task(id: selectedConversationID) {
                    cancelPendingDiffActionIfNeeded()
                }
        }
    }

    private func createConversation() async {
        guard let dbThread = uiModelContext.model(for: thread.persistentModelID) as? AgentThread else {
            createConversationError = "Couldn't create conversation: thread no longer exists"
            return
        }
        let conversation = Conversation()
        conversation.isMain = false
        conversation.displayOrder = (dbThread.conversations.map(\.displayOrder).max() ?? -1) + 1
        conversation.provider = dbThread.conversations.first(where: { $0.isMain })?.provider
            ?? dbThread.conversations.first?.provider
        conversation.thread = dbThread
        uiModelContext.insert(conversation)
        do {
            try uiModelContext.save()
            createConversationError = nil
            guard case .thread(let selectedThread) = appState.selectedSidebarItem,
                  selectedThread.persistentModelID == thread.persistentModelID else { return }
            appState.selectConversation(conversation, in: thread)
            if let path = dbThread.worktreePath ?? dbThread.project?.path {
                let baseRef = dbThread.project?.baseRef ?? "main"
                let remoteName = dbThread.project?.remoteName
                let conversationIds = Set(dbThread.conversations.map(\.id))
                // Same-directory rebind: a new side conversation should immediately count
                // as part of this thread's shared diff context so its later turn-complete
                // notifications refresh the right pane and changed-files strip.
                await diffViewModel.switchToDirectory(
                    path,
                    baseRef: baseRef,
                    remoteName: remoteName,
                    conversationIds: conversationIds
                )
            }
        } catch {
            createConversationError = "Couldn't create conversation: \(error.localizedDescription)"
        }
    }

    private func cancelPendingDiffActionIfNeeded() {
        guard let request = appState.pendingDiffAction else { return }
        guard request.conversationID == selectedConversationID else {
            appState.pendingDiffAction = nil
            return
        }
    }
}
```

Minimal tab-bar signature:

```swift
struct ConversationTabs: View {  // Skep/Views/Chat/ConversationTabs.swift
    let conversations: [Conversation]
    let selectedConversation: Conversation
    let statusForConversation: (Conversation) -> ActivitySignal
    let onSelect: (Conversation) -> Void
    let onCreate: () -> Void
}
```

**Snapshot tests for `ThreadDetailView` / `ConversationTabs`:** cover the states that are easy to regress when tab visibility and status dots depend on thread shape. Non-obvious:
- Single-conversation thread (tab bar hidden)
- Multi-conversation thread with mixed busy/error/idle dots
- Inline `createConversationError` banner above the tabs

Dependency boundary: `ContentView` is the composition root. It resolves services from Knit once, then `MiddlePane`, `ThreadDetailView`, and deeper chat views receive explicit collaborators instead of carrying `Resolver` forward, so the chat subtree does not become a hidden service-locator graph.

Content mapping:
- **Skills** selected → Skills management screen.
- **MCP** selected → MCP server management screen.
- **Project** selected → Project settings (path, base ref, GitHub, config file).
- **Thread** selected → `ThreadDetailView`, which owns the conversation tab bar, side-conversation creation, and the currently selected `ConversationView`. The selected tab is tracked separately from sidebar selection in app-session-only `AppState.selectedConversationIDs`, but stale bookmark healing runs via `repairSelectedConversationIfNeeded(for:)` in `.task` / explicit selection effects rather than mutating `AppState` during `body` evaluation. The centered "Create your first conversation" empty state is therefore reserved for truly empty threads, not normal relaunch or recovery paths.
- **Nothing selected + no projects** → First-run empty state.
- **Nothing selected + projects exist** → Neutral selection placeholder (for example, "Select a project or thread") rather than the first-run importer. This is the normal relaunch state because `AppState.selectedSidebarItem` is launch-scoped UI state, not persisted navigation.

Because the right pane is mounted by `ContentView`, not by `ThreadDetailView`, diff-viewer action taps use an `AppState.pendingDiffAction` handoff. `ContentView` snapshots the currently selected conversation's identifier only while the middle pane is actively showing a thread; the matching `ConversationView` consumes that one-shot request and routes it through `queueOrSend()`. Cancellation has two owners: `ContentView` clears the request when the middle-pane selection stops matching the snapshotted conversation ID, and `ThreadDetailView` clears it when the user changes side-conversation tabs inside the same thread before the target conversation consumes it. That keeps the request scoped to the currently visible chat instead of replaying later if the user switches back. Settings can preserve the old thread's diff content for inspection, but **Commit** / **Open PR** stay disabled there because no `ConversationView` is mounted to receive the request.

The shared diff context must also stay in sync when sidebar selection does **not** change: `ConversationView` rebinds the diff VM when first-message setup switches a selected thread from project root to worktree, and `ThreadDetailView.createConversation()` reuses the same-directory `switchToDirectory()` fast path so `activeConversationIds` grows immediately when side chats are added.

Use the SwiftUI environment `modelContext` for bookmark resolution, selection repair, and side-conversation creation. Injected view models such as `SidebarViewModel` and `ConversationViewModel` still use the stable write context handed down from `ContentView`.

### Right Pane (Diff Viewer)

Toggleable via a toolbar button (sidebar.trailing icon). Implemented as a conditional section within the `HStack` inside the `NavigationSplitView` detail pane — not as a separate `NavigationSplitView` column. Toggle uses `withAnimation(.easeInOut(duration: 0.25))` + `.clipped()` for a smooth push-from-right transition. `appState.isRightPaneVisible` is launch-scoped UI state, so changing the middle-pane selection does not auto-close the pane, but app relaunch resets it back to hidden. True non-thread selections (`.project`, `.skills`, `.mcp`, or `nil`) clear the shared `DiffViewerViewModel` and leave the pane showing its empty placeholder with file watching off until a thread is selected again. Settings is the one exception: it is a temporary middle-pane replacement that preserves the prior non-archived thread-backed diff context for read-only inspection. If that preserved thread is archived or deleted while Settings is open, dismiss falls back to the parent project or empty state instead of reopening archived chat, and the diff pane clears with it. See the **Diff Viewer** section for full details.

### Menu Bar

- **Toggle left pane** button (sidebar icon).
- **Toggle right pane** button (diff/changes icon).
- **App-wide settings** button (gear icon) -- opens settings that are not project-specific (default provider, appearance, notifications, etc.).

### Visual Design

The app should use a modern macOS design language leveraging the **Liquid Glass** material introduced in macOS 26. The primary SwiftUI modifier is `.glassEffect(_:in:isEnabled:)`:

```swift
// Glass styles:
.glassEffect(.regular, in: .capsule)     // Standard translucent glass (default)
.glassEffect(.clear, in: .capsule)       // Higher transparency, for media-rich backgrounds

// Tinting and interactivity (chained on the Glass value):
.glassEffect(.regular.tint(.blue), in: .capsule)
// .glassEffect(.regular.interactive(), in: .capsule)  // iOS only — not used in this macOS app

// Shape parameter: .capsule (default), .circle, .ellipse, RoundedRectangle(cornerRadius:), etc.

// Group related glass elements with GlassEffectContainer:
GlassEffectContainer(spacing: 8) {
    // child views with .glassEffect(...)
}
```

Key areas:

- **Sidebar**: apply `.glassEffect(.regular)` to the left pane background for translucent depth.
- **Menu bar / toolbar**: glass material toolbar with vibrancy, matching system chrome.
- **Modals and sheets**: glass-backed sheets for skill detail and settings panels.
- **The chat content area** should remain opaque (solid background) for readability -- Liquid Glass is for chrome, not content areas.
- **Tab bars**: conversation tabs within a thread should use the glass tab bar style. Use `glassEffectID(_:in:)` with a `Namespace` for morphing transitions between tabs.
- **Buttons and controls**: standard SwiftUI controls automatically adopt Liquid Glass styling on macOS 26+. For custom buttons, apply `.glassEffect(.regular, in: .capsule)`.

Accessibility (reduced transparency, increased contrast, reduced motion) is handled automatically by the framework.

The overall aesthetic should feel native to macOS 26 -- not a web app ported to Mac.

---

### Other View Models

The remaining view models are documented in their feature sections:
- **SidebarViewModel** (`Skep/ViewModels/SidebarViewModel.swift`) -- see [Part 4b: Sidebar](part4b-sidebar.md)
- **DiffViewerViewModel** (`Skep/ViewModels/DiffViewerViewModel.swift`)
- **SkillsViewModel** (`Skep/ViewModels/SkillsViewModel.swift`)
- **MCPViewModel** (`Skep/ViewModels/MCPViewModel.swift`)
- **SettingsViewModel** (`Skep/ViewModels/SettingsViewModel.swift`) -- see [Part 1c: Settings UI](part1c-settings-ui.md)
