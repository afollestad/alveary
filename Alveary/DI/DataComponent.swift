import AppKit
import Foundation
import NeedleFoundation
import SwiftData

final class DataComponent: Component<EmptyDependency> {}

extension DataComponent {
    /// Startup cannot proceed with substitute storage: services would overwrite settings and lose access to history.
    /// Retry stays in this bootstrap loop, before any database-dependent UI or background service is created.
    @MainActor
    static func makeModelContainer(isStoredInMemoryOnly: Bool, persistentStoreURL: URL) -> ModelContainer {
        while true {
            do {
                return try openModelContainer(isStoredInMemoryOnly: isStoredInMemoryOnly, persistentStoreURL: persistentStoreURL)
            } catch {
                let alert = NSAlert()
                alert.alertStyle = .critical
                alert.messageText = "Alveary could not open its database"
                alert.informativeText = """
                Your existing database has been preserved. Retry after resolving the error, or quit Alveary.

                \(persistentStoreURL.path)

                \(String(reflecting: error))
                """
                alert.addButton(withTitle: "Retry")
                alert.addButton(withTitle: "Quit")
                NSApplication.shared.activate(ignoringOtherApps: true)
                if alert.runModal() != .alertFirstButtonReturn { exit(EXIT_FAILURE) }
            }
        }
    }

    @MainActor
    static func openModelContainer(isStoredInMemoryOnly: Bool, persistentStoreURL: URL) throws -> ModelContainer {
        if isStoredInMemoryOnly {
            return try ModelContainer(for: Schema(versionedSchema: AlvearySchema.self), configurations: .init(isStoredInMemoryOnly: true))
        }
        try FileManager.default.createDirectory(at: persistentStoreURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try ProjectWorkspaceStoreUpgrade.open(at: persistentStoreURL)
    }

    static func persistentStoreURL(in applicationSupportDirectory: URL) -> URL {
        applicationSupportDirectory.appendingPathComponent("Alveary", isDirectory: true).appendingPathComponent("Alveary.store")
    }
}
