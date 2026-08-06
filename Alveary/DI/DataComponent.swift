import Foundation
import NeedleFoundation
import SwiftData

final class DataComponent: Component<EmptyDependency> {}

extension DataComponent {
    /// Set when `makeModelContainer` had to move an unopenable store aside to launch.
    /// The app root consumes this once to tell the user their history was set aside.
    @MainActor private(set) static var lastRecoveredStoreURL: URL?

    @MainActor
    static func consumeLastRecoveredStoreURL() -> URL? {
        defer { lastRecoveredStoreURL = nil }
        return lastRecoveredStoreURL
    }

    @MainActor
    static func makeModelContainer(
        isStoredInMemoryOnly: Bool,
        persistentStoreURL: URL
    ) -> ModelContainer {
        do {
            return try makeContainer(
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                persistentStoreURL: persistentStoreURL
            )
        } catch {
            // An unopenable store must not brick the app: move it aside and start clean, the same
            // way `DefaultSessionManager` handles an undecodable session map. A store that is
            // absent — an unwritable Application Support, say — has nothing to move, so it stays fatal.
            guard !isStoredInMemoryOnly,
                  let recoveredStoreURL = moveStoreAside(at: persistentStoreURL) else {
                fatalError("Failed to create ModelContainer: \(error)")
            }

            do {
                let container = try makeContainer(
                    isStoredInMemoryOnly: isStoredInMemoryOnly,
                    persistentStoreURL: persistentStoreURL
                )
                lastRecoveredStoreURL = recoveredStoreURL
                return container
            } catch {
                fatalError("Failed to create ModelContainer after moving the previous store aside: \(error)")
            }
        }
    }

    static func persistentStoreURL(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("Alveary.store")
    }
}

private extension DataComponent {
    /// SQLite keeps `-wal` and `-shm` companions beside the store; leaving either behind next to a
    /// fresh store can fail the retry, so all three move together.
    static let storeSidecarSuffixes = ["-wal", "-shm"]

    static func makeContainer(
        isStoredInMemoryOnly: Bool,
        persistentStoreURL: URL
    ) throws -> ModelContainer {
        let configuration = try makeModelConfiguration(
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            persistentStoreURL: persistentStoreURL
        )
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
    }

    static func makeModelConfiguration(
        isStoredInMemoryOnly: Bool,
        persistentStoreURL: URL
    ) throws -> ModelConfiguration {
        if isStoredInMemoryOnly {
            return ModelConfiguration(isStoredInMemoryOnly: true)
        }

        try FileManager.default.createDirectory(
            at: persistentStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        return ModelConfiguration(url: persistentStoreURL)
    }

    static func moveStoreAside(at persistentStoreURL: URL) -> URL? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: persistentStoreURL.path) else {
            return nil
        }

        let destinationURL = persistentStoreURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(persistentStoreURL.lastPathComponent).corrupt-\(recoveryTimestamp())")

        do {
            try fileManager.moveItem(at: persistentStoreURL, to: destinationURL)
        } catch {
            return nil
        }

        for suffix in storeSidecarSuffixes {
            let sidecarURL = URL(fileURLWithPath: persistentStoreURL.path + suffix)
            guard fileManager.fileExists(atPath: sidecarURL.path) else {
                continue
            }
            try? fileManager.moveItem(
                at: sidecarURL,
                to: URL(fileURLWithPath: destinationURL.path + suffix)
            )
        }

        return destinationURL
    }

    static func recoveryTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
