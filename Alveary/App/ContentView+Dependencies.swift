import Knit
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
    static func resolve(_ resolver: Resolver) -> ContentViewDependencies {
        ContentViewDependencies(
            settingsService: resolver.settingsService(),
            shellRunner: resolver.shellRunner(),
            gitHubCLI: resolver.gitHubCLIService(),
            providerDetection: resolver.providerDetectionService(),
            agentRegistry: resolver.agentRegistry(),
            providerRegistry: resolver.providerRegistry(),
            skillsService: resolver.skillsService(),
            mcpService: resolver.mcpService(),
            agentsManager: resolver.agentsManager(),
            runtimeStore: resolver.conversationRuntimeStore(),
            worktreeManager: resolver.worktreeManager(),
            providerSetup: resolver.providerSetupService(),
            contextWindowCache: resolver.contextWindowCache(),
            fileListManager: resolver.fileListManager(),
            notificationManager: resolver.notificationManager(),
            notificationRouter: resolver.notificationRouter(),
            gitService: resolver.gitService(),
            gitHubService: resolver.gitHubService(),
            diffWorkspaceStore: resolver.diffWorkspaceStore(),
            modelContainer: resolver.modelContainer()
        )
    }
}
