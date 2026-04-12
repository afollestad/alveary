import Knit

final class AgentAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] {
        [DetectionAssembly.self, NotificationAssembly.self, SessionAssembly.self, SettingsAssembly.self]
    }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(AgentEnvironmentBuilder.self) { _ in
            DefaultAgentEnvironmentBuilder()
        }
        .inObjectScope(.container)

        container.register(ClaudeConfigStore.self) { _ in
            DefaultClaudeConfigStore()
        }
        .inObjectScope(.container)

        container.register(ProviderSetupService.self) { resolver in
            return DefaultProviderSetupService(
                claudeConfigStore: resolver.claudeConfigStore()
            )
        }
        .inObjectScope(.container)

        container.register(DefaultAgentsManager.self) { resolver in
            return DefaultAgentsManager(
                sessionManager: resolver.sessionManager(),
                providerDetection: resolver.providerDetectionService(),
                environmentBuilder: resolver.agentEnvironmentBuilder(),
                providerRegistry: resolver.providerRegistry(),
                settingsService: resolver.settingsService(),
                notificationManager: resolver.notificationManager()
            )
        }
        .inObjectScope(.container)

        container.register(AgentsManager.self) { resolver in
            resolver.defaultAgentsManager()
        }
        .inObjectScope(.container)

        container.register(ConversationRuntimeStore.self) { resolver in
            resolver.defaultAgentsManager()
        }
        .inObjectScope(.container)
    }
}
