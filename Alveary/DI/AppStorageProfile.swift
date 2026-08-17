import Foundation

// The profile is immutable after bootstrap, and `UserDefaults` supports concurrent access.
struct AppStorageProfile: @unchecked Sendable {
    private static let hostedUnitTestDefaultsSuitePrefix = "com.afollestad.alveary.hosted-unit-tests"
    private static let scratchDefaultsSuitePrefix = "com.afollestad.alveary.scratch"
    private static let scratchDirectoryName = "AlvearyScratch"
    private static let demoDefaultsSuiteName = "com.afollestad.alveary.demo"
    private static let demoDirectoryName = "AlvearyDemo"

    let applicationSupportBaseURL: URL
    let settingsDefaults: UserDefaults
    let settingsDefaultsSuiteName: String?
    /// Only ephemeral profiles opt into teardown. A scratch profile names a suite it must keep,
    /// so wiping cannot be inferred from `settingsDefaultsSuiteName` being non-nil.
    let wipesSettingsDefaultsOnExit: Bool
    /// Whether this is the DEBUG-only demo profile. `AppComponent+Demo.swift` branches on it to
    /// swap in the fake services, so it — not `AppRuntimeProfile.kind` — is the single source of
    /// truth; a computed `kind == .demo` could disagree with the storage actually in use.
    let isDemo: Bool

    init(
        applicationSupportBaseURL: URL,
        settingsDefaults: UserDefaults,
        settingsDefaultsSuiteName: String?,
        wipesSettingsDefaultsOnExit: Bool = false,
        isDemo: Bool = false
    ) {
        self.applicationSupportBaseURL = applicationSupportBaseURL
        self.settingsDefaults = settingsDefaults
        self.settingsDefaultsSuiteName = settingsDefaultsSuiteName
        self.wipesSettingsDefaultsOnExit = wipesSettingsDefaultsOnExit
        self.isDemo = isDemo
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

    #if DEBUG
    /// Isolated storage for the DEBUG-only demo mode, wiped on every launch so screenshots are
    /// deterministic. The opposite contract to `scratch(name:)`, which deliberately survives quit.
    ///
    /// Deletion happens here, in the factory, before the store is opened — `AppRuntimeProfile`
    /// resolves the profile before the model container exists, so nothing has the tree open yet.
    /// Every failure is fatal rather than `try?`: a swallowed one would leave the seeder running
    /// against a populated store and double-seed it.
    static func demo(fileManager: FileManager = .default) -> AppStorageProfile {
        let baseURL = userApplicationSupportBaseURL
            .appendingPathComponent(demoDirectoryName, isDirectory: true)
        let suiteName = demoDefaultsSuiteName
        // Deliberately no `return .production` fallback: falling through would run demo mode
        // against the user's real storage, possibly after the wipe below already ran.
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create the demo UserDefaults suite: \(suiteName)")
        }

        // Held for this process's lifetime, and taken before the wipe: a predecessor demo instance
        // still holds it while its store is open. `DemoStorageLock` documents why the wait cannot
        // instead be on that predecessor's process exit.
        DemoStorageLock.acquire(at: demoStorageLockURL)
        wipeDemoStorage(at: baseURL, suiteName: suiteName, defaults: defaults, fileManager: fileManager)

        let profile = AppStorageProfile(
            applicationSupportBaseURL: baseURL,
            settingsDefaults: defaults,
            // Wiped on *entry*, never on exit: an exit wipe would race a relaunching successor
            // that has already seeded the shared suite.
            settingsDefaultsSuiteName: suiteName,
            wipesSettingsDefaultsOnExit: false,
            isDemo: true
        )
        assert(
            !fileManager.fileExists(atPath: profile.mainStoreURL.path),
            "Demo store already exists after the wipe; something opened it before the profile resolved"
        )
        return profile
    }

    /// Sibling of the demo tree, never a file inside it: `wipeDemoStorage` deletes that directory
    /// whole, and a lock file that went with it would leave the next instance locking a fresh inode
    /// no live predecessor holds — acquiring instantly while the store is still open.
    static var demoStorageLockURL: URL {
        userApplicationSupportBaseURL.appendingPathComponent("\(demoDirectoryName).lock")
    }

    /// Guards the delete target before removing it. This is the most destructive code in the app,
    /// and the suite name in particular is load-bearing: `removePersistentDomain` on the main
    /// bundle identifier would erase the user's entire real preference domain.
    private static func wipeDemoStorage(
        at baseURL: URL,
        suiteName: String,
        defaults: UserDefaults,
        fileManager: FileManager
    ) {
        guard suiteName.hasPrefix("com.afollestad.alveary."),
              suiteName != Bundle.main.bundleIdentifier else {
            fatalError("Refusing to wipe a demo defaults suite that is not demo-scoped: \(suiteName)")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let standardizedBaseURL = baseURL.standardizedFileURL
        let expectedParentPath = userApplicationSupportBaseURL.standardizedFileURL.path
        guard standardizedBaseURL.lastPathComponent == demoDirectoryName,
              standardizedBaseURL.deletingLastPathComponent().path == expectedParentPath else {
            fatalError("Refusing to wipe an unexpected demo directory: \(standardizedBaseURL.path)")
        }

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: standardizedBaseURL.path, isDirectory: &isDirectory) else {
            return
        }
        guard isDirectory.boolValue else {
            fatalError("Refusing to wipe a demo path that is not a directory: \(standardizedBaseURL.path)")
        }
        do {
            try fileManager.removeItem(at: standardizedBaseURL)
        } catch {
            fatalError("Failed to wipe the demo storage directory: \(error.localizedDescription)")
        }
    }
    #endif

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

    var reviewProposalPreviewCacheFileURL: URL {
        appSupportDirectory.appendingPathComponent("ReviewProposalPreviewCache.json")
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
