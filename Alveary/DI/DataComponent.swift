import Foundation
import NeedleFoundation
import SwiftData

final class DataComponent: Component<EmptyDependency> {}

extension DataComponent {
    static func makeModelContainer(isStoredInMemoryOnly: Bool) -> ModelContainer {
        do {
            let configuration = try makeModelConfiguration(isStoredInMemoryOnly: isStoredInMemoryOnly)
            return try ModelContainer(
                for: Project.self,
                AgentThread.self,
                Conversation.self,
                ConversationEventRecord.self,
                ScheduledTask.self,
                ScheduledTaskRun.self,
                ScheduledTaskProposal.self,
                configurations: configuration
            )
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }

    static func persistentStoreURL(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("Alveary.store")
    }
}

private extension DataComponent {
    static func makeModelConfiguration(isStoredInMemoryOnly: Bool) throws -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        }

        let applicationSupportDirectory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let storeURL = persistentStoreURL(in: applicationSupportDirectory)

        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return ModelConfiguration(url: storeURL)
    }
}
