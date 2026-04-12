import Foundation
import Knit

final class SessionAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [] }

    @MainActor
    func assemble(container: Container<Resolver>) {
        container.register(SessionManager.self) { _ in
            DefaultSessionManager(supportDirectory: Self.appSupportDirectory)
        }
        .inObjectScope(.container)
    }

    private static var appSupportDirectory: URL {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return baseURL.appendingPathComponent("com.afollestad.alveary", isDirectory: true)
    }
}
