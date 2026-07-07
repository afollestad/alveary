import AgentCLIKit
import SwiftData

struct ContentViewDependencies {
    let settingsService: SettingsService
    let shellRunner: ShellRunner
    let gitHubCLI: GitHubCLIService
    let providerDetection: any ProviderDetectionService
    let providerDiscovery: any AgentCLIKit.AgentProviderDiscoveryService
    let agentRegistry: AgentRegistry
    let providerRegistry: ProviderRegistry
    let skillsService: SkillsService
    let mcpService: MCPService
    let agentsManager: any AgentsManager
    let agentOneShotPromptService: any AgentOneShotPromptService
    let runtimeStore: any ConversationRuntimeStore
    let keepAwakeService: KeepAwakeService
    let worktreeManager: WorktreeManager
    let providerSessionActions: any ProviderSessionActionService
    let providerSetup: ProviderSetupService
    let contextWindowCache: any ContextWindowCache
    let fileListManager: FileListManager
    let notificationManager: any NotificationManager
    let notificationRouter: NotificationRouter
    let appUpdateManager: AppUpdateManager
    let threadActivityRecorder: any ThreadActivityRecording
    let gitService: GitService
    let diffWorkspaceStore: DiffWorkspaceStore
    let modelContainer: ModelContainer

    @MainActor
    static func resolve(_ component: AppComponent) -> ContentViewDependencies {
        ContentViewDependencies(
            settingsService: component.settingsService,
            shellRunner: component.shellRunner,
            gitHubCLI: component.gitHubCLIService,
            providerDetection: component.providerDetectionService,
            providerDiscovery: component.agentCLIKitProviderDiscoveryService,
            agentRegistry: component.agentRegistry,
            providerRegistry: component.providerRegistry,
            skillsService: component.skillsService,
            mcpService: component.mcpService,
            agentsManager: component.agentsManager,
            agentOneShotPromptService: component.agentOneShotPromptService,
            runtimeStore: component.conversationRuntimeStore,
            keepAwakeService: component.keepAwakeService,
            worktreeManager: component.worktreeManager,
            providerSessionActions: component.providerSessionActionService,
            providerSetup: component.providerSetupService,
            contextWindowCache: component.contextWindowCache,
            fileListManager: component.fileListManager,
            notificationManager: component.notificationManager,
            notificationRouter: component.notificationRouter,
            appUpdateManager: component.appUpdateManager,
            threadActivityRecorder: component.threadActivityRecorder,
            gitService: component.gitService,
            diffWorkspaceStore: component.diffWorkspaceStore,
            modelContainer: component.modelContainer
        )
    }
}
