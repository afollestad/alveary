import Knit
import SwiftData

final class NotificationAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [DataAssembly.self, SettingsAssembly.self] }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(NotificationRouter.self) { _ in
            NotificationRouter()
        }
        .inObjectScope(.container)

        container.register(NotificationManager.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            guard let settingsService = unsafeResolver.resolve(SettingsService.self) else {
                fatalError("SettingsService was not registered before NotificationManager")
            }
            guard let modelContainer = unsafeResolver.resolve(ModelContainer.self) else {
                fatalError("ModelContainer was not registered before NotificationManager")
            }

            return DefaultNotificationManager(
                settingsService: settingsService,
                modelContainer: modelContainer
            )
        }
        .inObjectScope(.container)
    }
}
