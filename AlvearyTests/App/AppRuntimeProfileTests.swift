import AgentCLIKit
import AppKit
import Foundation
import XCTest

@testable import Alveary

@MainActor
final class AppRuntimeProfileTests: XCTestCase {
    func testExplicitHostedUnitTestMarkerSelectsHostedProfile() {
        XCTAssertEqual(
            AppRuntimeProfile.detectKind(environment: [
                AppRuntimeProfile.hostedUnitTestEnvironmentKey: "1"
            ]),
            .hostedUnitTest
        )
    }

    func testXCTestInjectionLibrarySelectsHostedProfileAsFallback() {
        XCTAssertEqual(
            AppRuntimeProfile.detectKind(environment: [
                "DYLD_INSERT_LIBRARIES": "/tmp/libOne.dylib:/tmp/libXCTestBundleInject.dylib"
            ]),
            .hostedUnitTest
        )
    }

    func testAlvearyTestBundlePathSelectsHostedProfileAsFallback() {
        XCTAssertEqual(
            AppRuntimeProfile.detectKind(environment: [
                "XCTestBundlePath": "/tmp/Alveary.app/Contents/PlugIns/AlvearyTests.xctest"
            ]),
            .hostedUnitTest
        )
    }

    func testNormalAndPreviewEnvironmentsRemainApplicationProfiles() {
        XCTAssertEqual(AppRuntimeProfile.detectKind(environment: [:]), .application)
        XCTAssertEqual(
            AppRuntimeProfile.detectKind(environment: ["XCODE_RUNNING_FOR_PREVIEWS": "1"]),
            .application
        )
        XCTAssertEqual(
            AppRuntimeProfile.detectKind(environment: [
                AppRuntimeProfile.hostedUnitTestEnvironmentKey: "0",
                "XCTestConfigurationFilePath": "/tmp/unrelated.xctestconfiguration"
            ]),
            .application
        )
        XCTAssertEqual(
            AppRuntimeProfile.detectKind(environment: [
                "XCTestBundlePath": "/tmp/UnrelatedTests.xctest"
            ]),
            .application
        )
    }

    func testProductionStorageProfilePreservesDataAndPreferencePaths() {
        let profile = AppStorageProfile.production
        let baseURL = productionApplicationSupportBaseURL
        let alvearyDirectory = baseURL.appendingPathComponent("Alveary", isDirectory: true)
        let appSupportDirectory = baseURL.appendingPathComponent("com.afollestad.alveary", isDirectory: true)

        XCTAssertEqual(
            profile.mainStoreURL,
            alvearyDirectory.appendingPathComponent("Alveary.store")
        )
        XCTAssertEqual(profile.appSupportDirectory, appSupportDirectory)
        XCTAssertTrue(profile.settingsDefaults === UserDefaults.standard)
        XCTAssertNil(profile.settingsDefaultsSuiteName)
    }

    func testProductionStorageProfilePreservesServicePaths() {
        let profile = AppStorageProfile.production
        let baseURL = productionApplicationSupportBaseURL
        let alvearyDirectory = baseURL.appendingPathComponent("Alveary", isDirectory: true)
        let appSupportDirectory = baseURL.appendingPathComponent("com.afollestad.alveary", isDirectory: true)
        let taskWorkspacesDirectory = appSupportDirectory.appendingPathComponent("TaskWorkspaces", isDirectory: true)

        XCTAssertEqual(
            profile.contextWindowCacheFileURL,
            alvearyDirectory
                .appendingPathComponent("ContextWindows", isDirectory: true)
                .appendingPathComponent("context-window-sizes.json")
        )
        XCTAssertEqual(
            profile.approvalSupportDirectory,
            alvearyDirectory.appendingPathComponent("ClaudeHooks", isDirectory: true)
        )
        XCTAssertEqual(
            profile.conversationAttachmentsDirectory,
            appSupportDirectory.appendingPathComponent("ConversationAttachments", isDirectory: true)
        )
        XCTAssertEqual(
            profile.privateTaskWorkspacesDirectory,
            taskWorkspacesDirectory.appendingPathComponent("Private", isDirectory: true)
        )
        XCTAssertEqual(
            profile.worktreeOwnershipRecordsDirectory,
            taskWorkspacesDirectory.appendingPathComponent("WorktreeOwnership", isDirectory: true)
        )
        XCTAssertEqual(
            profile.voiceInputModelsDirectory,
            appSupportDirectory
                .appendingPathComponent("VoiceInput", isDirectory: true)
                .appendingPathComponent("Models", isDirectory: true)
        )
        XCTAssertEqual(
            profile.updatesDirectory,
            appSupportDirectory.appendingPathComponent("Updates", isDirectory: true)
        )
    }

    func testProductionStorageProfilePreservesAgentCLIKitPaths() {
        let profile = AppStorageProfile.production
        let agentCLIKitDirectory = productionApplicationSupportBaseURL
            .appendingPathComponent("com.afollestad.alveary", isDirectory: true)
            .appendingPathComponent("AgentCLIKit", isDirectory: true)

        XCTAssertEqual(profile.agentCLIKitSupportDirectory, agentCLIKitDirectory)
        XCTAssertEqual(
            profile.agentCLIKitHookSupportDirectory,
            agentCLIKitDirectory.appendingPathComponent("ClaudeHooks", isDirectory: true)
        )
        XCTAssertEqual(
            profile.agentCLIKitContextWindowCacheFileURL,
            agentCLIKitDirectory.appendingPathComponent("context-windows.json")
        )
        XCTAssertEqual(
            profile.agentCLIKitSessionStoreFileURL,
            agentCLIKitDirectory.appendingPathComponent("sessions.json")
        )
    }

    func testHostedStorageProfilesAreUniqueAndUseTemporaryState() throws {
        let first = AppStorageProfile.hostedUnitTest(processIdentifier: 42, identifier: UUID())
        let second = AppStorageProfile.hostedUnitTest(processIdentifier: 42, identifier: UUID())
        defer {
            first.cleanupSettingsDefaults()
            second.cleanupSettingsDefaults()
        }

        XCTAssertNotEqual(first.applicationSupportBaseURL, second.applicationSupportBaseURL)
        XCTAssertNotEqual(first.settingsDefaultsSuiteName, second.settingsDefaultsSuiteName)
        XCTAssertTrue(
            first.applicationSupportBaseURL.path.hasPrefix(FileManager.default.temporaryDirectory.path)
        )
        XCTAssertNotEqual(
            first.applicationSupportBaseURL.standardizedFileURL,
            AppStorageProfile.production.applicationSupportBaseURL.standardizedFileURL
        )
        for writableURL in first.appOwnedWritableURLs {
            XCTAssertTrue(writableURL.isDescendant(of: first.applicationSupportBaseURL))
            XCTAssertFalse(writableURL.isDescendant(of: AppStorageProfile.production.applicationSupportBaseURL))
        }

        let suiteName = try XCTUnwrap(first.settingsDefaultsSuiteName)
        first.settingsDefaults.set("isolated", forKey: "AppRuntimeProfileTests")
        XCTAssertEqual(first.settingsDefaults.string(forKey: "AppRuntimeProfileTests"), "isolated")
        XCTAssertEqual(first.settingsDefaults.persistentDomain(forName: suiteName)?["AppRuntimeProfileTests"] as? String, "isolated")
        first.cleanupSettingsDefaults()
        XCTAssertTrue(first.settingsDefaults.persistentDomain(forName: suiteName)?.isEmpty ?? true)
    }

    func testHostedProcessUsesRealAppDIWithIsolatedPersistentStorage() {
        XCTAssertEqual(
            ProcessInfo.processInfo.environment[AppRuntimeProfile.hostedUnitTestEnvironmentKey],
            "1"
        )
        XCTAssertEqual(AppRuntimeProfile.current.kind, .hostedUnitTest)
        let profile = AppRuntimeProfile.current.storageProfile
        let component = AppDI.component

        XCTAssertEqual(component.storageProfile.applicationSupportBaseURL, profile.applicationSupportBaseURL)
        XCTAssertNotEqual(
            profile.applicationSupportBaseURL.standardizedFileURL,
            AppStorageProfile.production.applicationSupportBaseURL.standardizedFileURL
        )

        resolveProductionServiceGraph(component)
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.mainStoreURL.path))

        XCTAssertNotNil(profile.settingsDefaults.data(forKey: UserDefaultsSettingsService.storageKey))

        let appOwnedWindowTitles = Set(["Alveary", "Raw Transcript"])
        XCTAssertFalse(NSApp.windows.contains { $0.isVisible && appOwnedWindowTitles.contains($0.title) })
    }

    func testInMemoryTestComponentStillUsesHostedStorageProfileForFileBackedServices() {
        let component = AppDI.makeTestComponent(isStoredInMemoryOnly: true)

        XCTAssertEqual(
            component.storageProfile.applicationSupportBaseURL,
            AppRuntimeProfile.current.storageProfile.applicationSupportBaseURL
        )
        XCTAssertEqual(
            component.conversationAttachmentStore.conversationRootDirectory(conversationId: "test").deletingLastPathComponent(),
            AppRuntimeProfile.current.storageProfile.conversationAttachmentsDirectory
                .appendingPathComponent("conversations", isDirectory: true)
        )
    }

    func testExplicitStorageProfileInjectionRoutesFileBackedServices() async throws {
        let profile = AppStorageProfile.hostedUnitTest(processIdentifier: 43, identifier: UUID())
        defer { profile.cleanupSettingsDefaults() }
        let component = AppDI.makeTestComponent(
            isStoredInMemoryOnly: true,
            storageProfile: profile
        )

        XCTAssertEqual(component.storageProfile.applicationSupportBaseURL, profile.applicationSupportBaseURL)
        await assertCoreStorageServices(component, use: profile)
        try await assertAgentCLIKitStorageServices(component, use: profile)
        try await assertOwnedDirectoryServices(component, use: profile)
    }

    private var productionApplicationSupportBaseURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(
                "Library/Application Support",
                isDirectory: true
            )
    }

    private func resolveProductionServiceGraph(_ component: AppComponent) {
        _ = component.modelContainer
        _ = component.modelContext
        _ = component.settingsService
        _ = component.sessionManager
        _ = component.conversationAttachmentStore
        _ = component.contextWindowCache
        _ = component.notificationManager
        _ = component.appUpdateManager
        _ = component.providerSetupService
        _ = component.agentCLIKitHostServices
        _ = component.claudeApprovalPersistenceStore
        _ = component.agentsManager
        _ = component.agentOneShotPromptService
        _ = component.gitService
        _ = component.worktreeManager
        _ = component.taskWorkspaceOwnershipService
        _ = component.diffWorkspaceStore
        _ = component.gitHubCLIService
        _ = component.skillsService
        _ = component.mcpService
        _ = component.voiceInputLifecycleController
        _ = component.onboardingDependencyService
        _ = component.scheduledTaskLifecycleCoordinator
    }

    private func assertCoreStorageServices(
        _ component: AppComponent,
        use profile: AppStorageProfile
    ) async {
        _ = component.settingsService
        XCTAssertNotNil(profile.settingsDefaults.data(forKey: UserDefaultsSettingsService.storageKey))

        _ = await component.sessionManager.createEntry(
            conversationId: "storage-profile-test",
            cwd: "/tmp",
            providerId: "codex"
        )
        let sessionFileURL = profile.appSupportDirectory.appendingPathComponent("session-map.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: sessionFileURL.path))

        await component.contextWindowCache.update(
            providerId: "codex",
            selectedModel: "storage-profile-test",
            reportedModelId: nil,
            contextWindowSize: 1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.contextWindowCacheFileURL.path))
    }

    private func assertAgentCLIKitStorageServices(
        _ component: AppComponent,
        use profile: AppStorageProfile
    ) async throws {
        try await component.agentCLIKitContextWindowCache.update(
            providerId: .codex,
            selectedModel: "storage-profile-test",
            contextWindowSize: 1
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.agentCLIKitContextWindowCacheFileURL.path))

        try await component.agentCLIKitSessionStore.remove(
            conversationId: "storage-profile-test",
            providerId: .codex
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: profile.agentCLIKitSessionStoreFileURL.path))

        _ = try XCTUnwrap(
            component.claudeApprovalPersistenceStore as? DefaultClaudeApprovalPersistenceStore
        )
        let approvalStoreURL = profile.approvalSupportDirectory.appendingPathComponent("session-approvals.store")
        XCTAssertTrue(FileManager.default.fileExists(atPath: approvalStoreURL.path))
    }

    private func assertOwnedDirectoryServices(
        _ component: AppComponent,
        use profile: AppStorageProfile
    ) async throws {
        XCTAssertEqual(
            component.conversationAttachmentStore
                .conversationRootDirectory(conversationId: "test")
                .deletingLastPathComponent(),
            profile.conversationAttachmentsDirectory.appendingPathComponent("conversations", isDirectory: true)
        )

        let taskWorkspaceService = try XCTUnwrap(
            component.taskWorkspaceOwnershipService as? DefaultTaskWorkspaceOwnershipService
        )
        XCTAssertEqual(taskWorkspaceService.privateWorkspacesRoot, profile.privateTaskWorkspacesDirectory)
        XCTAssertEqual(taskWorkspaceService.worktreeOwnershipRecordsRoot, profile.worktreeOwnershipRecordsDirectory)

        let voiceInputService = try XCTUnwrap(component.voiceInputService as? DefaultVoiceInputService)
        let modelRepository = await voiceInputService.modelRepository
        let voiceModelRepository = try XCTUnwrap(modelRepository as? DefaultVoiceInputModelRepository)
        let modelsDirectory = await voiceModelRepository.modelsDirectory
        let cacheOwnershipDirectory = await voiceModelRepository.cacheOwnershipDirectory
        XCTAssertEqual(modelsDirectory, profile.voiceInputModelsDirectory)
        XCTAssertEqual(cacheOwnershipDirectory, profile.appSupportDirectory)
    }
}

private extension AppStorageProfile {
    var appOwnedWritableURLs: [URL] {
        [
            mainStoreURL,
            appSupportDirectory,
            agentCLIKitSupportDirectory,
            agentCLIKitHookSupportDirectory,
            agentCLIKitContextWindowCacheFileURL,
            agentCLIKitSessionStoreFileURL,
            contextWindowCacheFileURL,
            approvalSupportDirectory,
            conversationAttachmentsDirectory,
            privateTaskWorkspacesDirectory,
            worktreeOwnershipRecordsDirectory,
            voiceInputModelsDirectory,
            updatesDirectory
        ]
    }
}

private extension URL {
    func isDescendant(of root: URL) -> Bool {
        standardizedFileURL.path.hasPrefix(root.standardizedFileURL.path + "/")
    }
}
