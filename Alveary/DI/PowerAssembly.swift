import Knit

final class PowerAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [SettingsAssembly.self] }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(KeepAwakeService.self) { resolver in
            DefaultKeepAwakeService(settingsService: resolver.settingsService())
        }
        .inObjectScope(.container)
    }
}
