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
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return DefaultProviderSetupService(
                claudeConfigStore: unsafeResolver.resolve(ClaudeConfigStore.self) ?? {
                    fatalError("ClaudeConfigStore was not registered before ProviderSetupService")
                }()
            )
        }
        .inObjectScope(.container)

        container.register(DefaultAgentsManager.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return DefaultAgentsManager(
                sessionManager: unsafeResolver.resolve(SessionManager.self) ?? {
                    fatalError("SessionManager was not registered before DefaultAgentsManager")
                }(),
                providerDetection: unsafeResolver.resolve(ProviderDetectionService.self) ?? {
                    fatalError("ProviderDetectionService was not registered before DefaultAgentsManager")
                }(),
                environmentBuilder: unsafeResolver.resolve(AgentEnvironmentBuilder.self) ?? {
                    fatalError("AgentEnvironmentBuilder was not registered before DefaultAgentsManager")
                }(),
                providerRegistry: unsafeResolver.resolve(ProviderRegistry.self) ?? {
                    fatalError("ProviderRegistry was not registered before DefaultAgentsManager")
                }(),
                settingsService: unsafeResolver.resolve(SettingsService.self) ?? {
                    fatalError("SettingsService was not registered before DefaultAgentsManager")
                }(),
                notificationManager: unsafeResolver.resolve(NotificationManager.self) ?? {
                    fatalError("NotificationManager was not registered before DefaultAgentsManager")
                }()
            )
        }
        .inObjectScope(.container)

        container.register(AgentsManager.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)
            guard let manager = unsafeResolver.resolve(DefaultAgentsManager.self) else {
                fatalError("DefaultAgentsManager was not registered before AgentsManager")
            }
            return manager
        }
        .inObjectScope(.container)

        container.register(ConversationRuntimeStore.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)
            guard let manager = unsafeResolver.resolve(DefaultAgentsManager.self) else {
                fatalError("DefaultAgentsManager was not registered before ConversationRuntimeStore")
            }
            return manager
        }
        .inObjectScope(.container)
    }
}
