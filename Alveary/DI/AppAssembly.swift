import Knit

final class AppAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [] }

    @MainActor
    func assemble(container: Container<Resolver>) {}
}
