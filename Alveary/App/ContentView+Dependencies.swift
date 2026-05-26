import SwiftData

struct ContentViewDependencies {
    let settingsService: SettingsService
    let shellRunner: ShellRunner
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    let agentRegistry: AgentRegistry
    let providerRegistry: ProviderRegistry
    let skillsService: SkillsService
    let mcpService: MCPService
    let agentsManager: any AgentsManager
    let runtimeStore: any ConversationRuntimeStore
    let keepAwakeService: KeepAwakeService
    let worktreeManager: WorktreeManager
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let notificationRouter: NotificationRouter
    let gitService: GitService
    let gitHubService: GitHubService
    let diffWorkspaceStore: DiffWorkspaceStore
    let modelContainer: ModelContainer

    @MainActor
    static func resolve(_ component: AppComponent) -> ContentViewDependencies {
        ContentViewDependencies(
            settingsService: component.settingsService,
            shellRunner: component.shellRunner,
            gitHubCLI: component.gitHubCLIService,
            providerDetection: component.providerDetectionService,
            agentRegistry: component.agentRegistry,
            providerRegistry: component.providerRegistry,
            skillsService: component.skillsService,
            mcpService: component.mcpService,
            agentsManager: component.agentsManager,
            runtimeStore: component.conversationRuntimeStore,
            keepAwakeService: component.keepAwakeService,
            worktreeManager: component.worktreeManager,
            providerSetup: component.providerSetupService,
            contextWindowCache: component.contextWindowCache,
            fileListManager: component.fileListManager,
            notificationManager: component.notificationManager,
            notificationRouter: component.notificationRouter,
            gitService: component.gitService,
            gitHubService: component.gitHubService,
            diffWorkspaceStore: component.diffWorkspaceStore,
            modelContainer: component.modelContainer
        )
    }
}
