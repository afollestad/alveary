import Foundation

// The profile is immutable after bootstrap, and `UserDefaults` supports concurrent access.
struct AppStorageProfile: @unchecked Sendable {
    private static let hostedUnitTestDefaultsSuitePrefix = "com.afollestad.alveary.hosted-unit-tests"
    private static let scratchDefaultsSuitePrefix = "com.afollestad.alveary.scratch"
    private static let scratchDirectoryName = "AlvearyScratch"

    let applicationSupportBaseURL: URL
    let settingsDefaults: UserDefaults
    let settingsDefaultsSuiteName: String?
    /// Only ephemeral profiles opt into teardown. A scratch profile names a suite it must keep,
    /// so wiping cannot be inferred from `settingsDefaultsSuiteName` being non-nil.
    let wipesSettingsDefaultsOnExit: Bool

    init(
        applicationSupportBaseURL: URL,
        settingsDefaults: UserDefaults,
        settingsDefaultsSuiteName: String?,
        wipesSettingsDefaultsOnExit: Bool = false
    ) {
        self.applicationSupportBaseURL = applicationSupportBaseURL
        self.settingsDefaults = settingsDefaults
        self.settingsDefaultsSuiteName = settingsDefaultsSuiteName
        self.wipesSettingsDefaultsOnExit = wipesSettingsDefaultsOnExit
    }

    static var production: AppStorageProfile {
        AppStorageProfile(
            applicationSupportBaseURL: userApplicationSupportBaseURL,
            settingsDefaults: .standard,
            settingsDefaultsSuiteName: nil
        )
    }

    /// Isolated but *stable* storage for manual first-run testing, selected by
    /// `AppRuntimeProfile.storageProfileEnvironmentKey`. Unlike `hostedUnitTest` it survives quit,
    /// so second-launch behavior such as skipping completed onboarding stays testable.
    static func scratch(name: String) -> AppStorageProfile {
        let sanitizedName = sanitizedScratchName(name)
        let baseURL = userApplicationSupportBaseURL
            .appendingPathComponent(scratchDirectoryName, isDirectory: true)
            .appendingPathComponent(sanitizedName, isDirectory: true)
        let suiteName = "\(scratchDefaultsSuitePrefix).\(sanitizedName)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            return .production
        }
        return AppStorageProfile(
            applicationSupportBaseURL: baseURL,
            settingsDefaults: defaults,
            settingsDefaultsSuiteName: suiteName
        )
    }

    static func sanitizedScratchName(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let sanitized = String(name.unicodeScalars.filter { allowed.contains($0) })
        return sanitized.isEmpty ? "default" : sanitized
    }

    private static var userApplicationSupportBaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
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
            settingsDefaultsSuiteName: suiteName,
            wipesSettingsDefaultsOnExit: true
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

    var pullRequestsListCacheFileURL: URL {
        appSupportDirectory.appendingPathComponent("PullRequestsListCache.json")
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
        guard wipesSettingsDefaultsOnExit,
              let settingsDefaultsSuiteName else {
            return
        }
        settingsDefaults.removePersistentDomain(forName: settingsDefaultsSuiteName)
        settingsDefaults.synchronize()
    }
}
