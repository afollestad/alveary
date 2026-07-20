import Foundation

// The profile is immutable after bootstrap, and `UserDefaults` supports concurrent access.
struct AppStorageProfile: @unchecked Sendable {
    private static let hostedUnitTestDefaultsSuitePrefix = "com.afollestad.alveary.hosted-unit-tests"

    let applicationSupportBaseURL: URL
    let settingsDefaults: UserDefaults
    let settingsDefaultsSuiteName: String?

    static var production: AppStorageProfile {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
        return AppStorageProfile(
            applicationSupportBaseURL: baseURL,
            settingsDefaults: .standard,
            settingsDefaultsSuiteName: nil
        )
    }

    static func hostedUnitTest(
        fileManager: FileManager = .default,
        processIdentifier: Int32 = ProcessInfo.processInfo.processIdentifier,
        identifier: UUID = UUID()
    ) -> AppStorageProfile {
        let profileID = "\(processIdentifier)-\(identifier.uuidString.lowercased())"
        let baseURL = fileManager.temporaryDirectory
            .appendingPathComponent("AlvearyHostedTests", isDirectory: true)
            .appendingPathComponent(profileID, isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
        let suiteName = "\(hostedUnitTestDefaultsSuitePrefix).\(profileID)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create hosted-unit-test UserDefaults suite: \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)
        return AppStorageProfile(
            applicationSupportBaseURL: baseURL,
            settingsDefaults: defaults,
            settingsDefaultsSuiteName: suiteName
        )
    }

    var mainStoreURL: URL {
        DataComponent.persistentStoreURL(in: applicationSupportBaseURL)
    }

    var appSupportDirectory: URL {
        applicationSupportBaseURL.appendingPathComponent("com.afollestad.alveary", isDirectory: true)
    }

    var agentCLIKitSupportDirectory: URL {
        appSupportDirectory.appendingPathComponent("AgentCLIKit", isDirectory: true)
    }

    var agentCLIKitHookSupportDirectory: URL {
        agentCLIKitSupportDirectory.appendingPathComponent("ClaudeHooks", isDirectory: true)
    }

    var agentCLIKitContextWindowCacheFileURL: URL {
        agentCLIKitSupportDirectory.appendingPathComponent("context-windows.json")
    }

    var agentCLIKitSessionStoreFileURL: URL {
        agentCLIKitSupportDirectory.appendingPathComponent("sessions.json")
    }

    var contextWindowCacheFileURL: URL {
        applicationSupportBaseURL
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("ContextWindows", isDirectory: true)
            .appendingPathComponent("context-window-sizes.json")
    }

    var approvalSupportDirectory: URL {
        applicationSupportBaseURL
            .appendingPathComponent("Alveary", isDirectory: true)
            .appendingPathComponent("ClaudeHooks", isDirectory: true)
    }

    var conversationAttachmentsDirectory: URL {
        appSupportDirectory.appendingPathComponent("ConversationAttachments", isDirectory: true)
    }

    var privateTaskWorkspacesDirectory: URL {
        appSupportDirectory
            .appendingPathComponent("TaskWorkspaces", isDirectory: true)
            .appendingPathComponent("Private", isDirectory: true)
    }

    var worktreeOwnershipRecordsDirectory: URL {
        appSupportDirectory
            .appendingPathComponent("TaskWorkspaces", isDirectory: true)
            .appendingPathComponent("WorktreeOwnership", isDirectory: true)
    }

    var voiceInputModelsDirectory: URL {
        appSupportDirectory
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
    }

    var updatesDirectory: URL {
        appSupportDirectory.appendingPathComponent("Updates", isDirectory: true)
    }

    func cleanupSettingsDefaults() {
        guard let settingsDefaultsSuiteName else {
            return
        }
        settingsDefaults.removePersistentDomain(forName: settingsDefaultsSuiteName)
        settingsDefaults.synchronize()
    }
}
