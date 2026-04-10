import Knit

final class DetectionAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] {
        [SettingsAssembly.self, ShellAssembly.self]
    }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(AgentRegistry.self) { _ in
            DefaultAgentRegistry()
        }
        .inObjectScope(.container)

        container.register(ProviderRegistry.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            guard let agentRegistry = unsafeResolver.resolve(AgentRegistry.self) else {
                fatalError("AgentRegistry was not registered before ProviderRegistry")
            }

            return DefaultProviderRegistry(agentRegistry: agentRegistry)
        }
        .inObjectScope(.container)

        container.register(ProviderDetectionService.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            guard let shellRunner = unsafeResolver.resolve(ShellRunner.self) else {
                fatalError("ShellRunner was not registered before ProviderDetectionService")
            }
            guard let providerRegistry = unsafeResolver.resolve(ProviderRegistry.self) else {
                fatalError("ProviderRegistry was not registered before ProviderDetectionService")
            }
            guard let settingsService = unsafeResolver.resolve(SettingsService.self) else {
                fatalError("SettingsService was not registered before ProviderDetectionService")
            }

            return DefaultProviderDetectionService(
                shell: shellRunner,
                registry: providerRegistry,
                loadSettings: {
                    await settingsService.current
                }
            )
        }
        .inObjectScope(.container)
    }
}
