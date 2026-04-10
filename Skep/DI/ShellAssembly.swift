import Knit

final class ShellAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [] }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(ShellRunner.self) { _ in
            DefaultShellRunner()
        }
        .inObjectScope(.container)
    }
}
