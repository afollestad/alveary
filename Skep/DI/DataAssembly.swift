import Knit
import SwiftData

final class DataAssembly: AutoInitModuleAssembly {
    typealias TargetResolver = Resolver

    static var dependencies: [any ModuleAssembly.Type] { [] }

    private let isStoredInMemoryOnly: Bool

    init() {
        self.isStoredInMemoryOnly = false
    }

    init(isStoredInMemoryOnly: Bool) {
        self.isStoredInMemoryOnly = isStoredInMemoryOnly
    }

    @MainActor
    func assemble(container: Container<Resolver>) {
        let isStoredInMemoryOnly = isStoredInMemoryOnly

        container.register(ModelContainer.self) { _ in
            let configuration = ModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly)

            do {
                return try ModelContainer(
                    for: Project.self,
                    AgentThread.self,
                    Conversation.self,
                    ConversationEventRecord.self,
                    configurations: configuration
                )
            } catch {
                fatalError("Failed to create ModelContainer: \(error)")
            }
        }
        .inObjectScope(.container)

        container.register(ModelContext.self) { resolver in
            let unsafeResolver = resolver.unsafeResolver(file: #fileID, function: #function, line: #line)

            guard let modelContainer = unsafeResolver.resolve(ModelContainer.self) else {
                fatalError("ModelContainer was not registered before ModelContext")
            }

            return ModelContext(modelContainer)
        }
        .inObjectScope(.container)
    }
}
