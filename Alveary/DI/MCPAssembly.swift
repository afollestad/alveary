import Knit

final class MCPAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] {
        [AgentAssembly.self, DetectionAssembly.self]
    }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(MCPService.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return DefaultMCPService(
                claudeConfigStore: unsafeResolver.resolve(ClaudeConfigStore.self) ?? {
                    fatalError("ClaudeConfigStore was not registered before MCPService")
                }(),
                providerDetection: unsafeResolver.resolve(ProviderDetectionService.self) ?? {
                    fatalError("ProviderDetectionService was not registered before MCPService")
                }(),
                agentRegistry: unsafeResolver.resolve(AgentRegistry.self) ?? {
                    fatalError("AgentRegistry was not registered before MCPService")
                }()
            )
        }
        .inObjectScope(.container)
    }
}
