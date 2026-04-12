import Knit

final class SettingsAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [] }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(SettingsService.self) { _ in
            UserDefaultsSettingsService()
        }
        .inObjectScope(.container)
    }
}
