import Knit

final class NotificationAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [SettingsAssembly.self] }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(NotificationManager.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            guard let settingsService = unsafeResolver.resolve(SettingsService.self) else {
                fatalError("SettingsService was not registered before NotificationManager")
            }

            return DefaultNotificationManager(settingsService: settingsService)
        }
        .inObjectScope(.container)
    }
}
