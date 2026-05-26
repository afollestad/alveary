import NeedleFoundation
import SwiftData

final class AppComponent: BootstrapComponent {
    private let isStoredInMemoryOnly: Bool

    init(isStoredInMemoryOnly: Bool = false) {
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
        super.init()
    }

    var dataComponent: DataComponent {
        return shared { DataComponent(parent: self) }
    }

    var settingsComponent: SettingsComponent {
        return shared { SettingsComponent(parent: self) }
    }

    var shellComponent: ShellComponent {
        return shared { ShellComponent(parent: self) }
    }

    var sessionComponent: SessionComponent {
        return shared { SessionComponent(parent: self) }
    }

    var notificationComponent: NotificationComponent {
        return shared { NotificationComponent(parent: self) }
    }

    var detectionComponent: DetectionComponent {
        return shared { DetectionComponent(parent: self) }
    }

    var powerComponent: PowerComponent {
        return shared { PowerComponent(parent: self) }
    }

    var agentComponent: AgentComponent {
        return shared { AgentComponent(parent: self) }
    }

    var gitComponent: GitComponent {
        return shared { GitComponent(parent: self) }
    }

    var gitHubComponent: GitHubComponent {
        return shared { GitHubComponent(parent: self) }
    }

    var skillsComponent: SkillsComponent {
        return shared { SkillsComponent(parent: self) }
    }

    var mcpComponent: MCPComponent {
        return shared { MCPComponent(parent: self) }
    }
}

@MainActor
extension AppComponent {
    var modelContainer: ModelContainer {
        return shared { DataComponent.makeModelContainer(isStoredInMemoryOnly: isStoredInMemoryOnly) }
    }

    var modelContext: ModelContext {
        return shared { ModelContext(modelContainer) }
    }

    var settingsService: SettingsService {
        return shared { UserDefaultsSettingsService() }
    }

    var shellRunner: ShellRunner {
        return shared { DefaultShellRunner() }
    }

    var sessionManager: SessionManager {
        return shared { DefaultSessionManager(supportDirectory: SessionComponent.appSupportDirectory) }
    }

    var notificationRouter: NotificationRouter {
        return shared { NotificationRouter() }
    }

    var notificationManager: NotificationManager {
        return shared {
            DefaultNotificationManager(
                settingsService: settingsService,
                modelContainer: modelContainer
            )
        }
    }

    var agentRegistry: AgentRegistry {
        return shared { DefaultAgentRegistry() }
    }

    var providerRegistry: ProviderRegistry {
        return shared { DefaultProviderRegistry(agentRegistry: agentRegistry) }
    }

    var providerDetectionService: ProviderDetectionService {
        return shared {
            DefaultProviderDetectionService(
                shell: shellRunner,
                registry: providerRegistry
            )
        }
    }

    var keepAwakeService: KeepAwakeService {
        return shared { DefaultKeepAwakeService(settingsService: settingsService) }
    }

    var agentEnvironmentBuilder: AgentEnvironmentBuilder {
        return shared { DefaultAgentEnvironmentBuilder() }
    }

    var claudeConfigStore: ClaudeConfigStore {
        return shared { DefaultClaudeConfigStore() }
    }

    var providerSetupService: ProviderSetupService {
        return shared { DefaultProviderSetupService(claudeConfigStore: claudeConfigStore) }
    }

    var contextWindowCache: ContextWindowCache {
        return shared { JSONContextWindowCache() }
    }

    var claudeHookServer: ClaudeHookServer {
        return shared { DefaultClaudeHookServer() }
    }

    var defaultAgentsManager: DefaultAgentsManager {
        return shared {
            DefaultAgentsManager(
                sessionManager: sessionManager,
                providerDetection: providerDetectionService,
                environmentBuilder: agentEnvironmentBuilder,
                providerRegistry: providerRegistry,
                settingsService: settingsService,
                keepAwakeService: keepAwakeService,
                notificationManager: notificationManager,
                claudeHookServer: claudeHookServer
            )
        }
    }

    var agentsManager: AgentsManager {
        return defaultAgentsManager
    }

    var conversationRuntimeStore: ConversationRuntimeStore {
        return defaultAgentsManager
    }

    var gitService: GitService {
        return shared { CLIGitService(shell: shellRunner) }
    }

    var worktreeManager: WorktreeManager {
        return shared {
            DefaultWorktreeManager(
                settingsService: settingsService,
                shell: shellRunner
            )
        }
    }

    var fileListManager: FileListManager {
        return shared { GitFileListManager(gitService: gitService) }
    }

    var diffWorkspaceStore: DiffWorkspaceStore {
        return shared { DiffWorkspaceStore(gitService: gitService) }
    }

    var gitHubCLIService: GitHubCLIService {
        return shared { DefaultGitHubCLIService(shell: shellRunner) }
    }

    var gitHubService: GitHubService {
        return shared { CLIGitHubService(ghCLI: gitHubCLIService) }
    }

    var skillsService: SkillsService {
        return shared { DefaultSkillsService(agentRegistry: agentRegistry) }
    }

    var mcpService: MCPService {
        return shared {
            DefaultMCPService(
                claudeConfigStore: claudeConfigStore,
                providerDetection: providerDetectionService,
                agentRegistry: agentRegistry
            )
        }
    }
}
