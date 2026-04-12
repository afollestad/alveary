import Knit

final class SkillsAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] {
        [DetectionAssembly.self]
    }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(SkillsService.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            return DefaultSkillsService(
                agentRegistry: unsafeResolver.resolve(AgentRegistry.self) ?? {
                    fatalError("AgentRegistry was not registered before SkillsService")
                }()
            )
        }
        .inObjectScope(.container)
    }
}
