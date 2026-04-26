import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class SettingsServiceTests: XCTestCase {
    func testUserDefaultsSettingsServiceLoadsDefaultValues() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current, AppSettings())
    }

    func testUserDefaultsSettingsServicePersistsUpdatesAcrossReloads() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update {
            $0.permissionMode = "plan"
            $0.effort = "high"
            $0.deleteKeyAction = .delete
            $0.reopenLastThreadAndConversationOnLaunch = false
            $0.branchPrefix = "feature/"
            $0.diffViewerWidth = 520
            $0.expandTerminalWhenActionsRun = true
            $0.maxTerminalSessions = 12
        }

        let reloadedService = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(reloadedService.current.permissionMode, "plan")
        XCTAssertEqual(reloadedService.current.effort, "high")
        XCTAssertEqual(reloadedService.current.deleteKeyAction, .delete)
        XCTAssertFalse(reloadedService.current.reopenLastThreadAndConversationOnLaunch)
        XCTAssertEqual(reloadedService.current.branchPrefix, "feature/")
        XCTAssertEqual(reloadedService.current.diffViewerWidth, 520)
        XCTAssertTrue(reloadedService.current.expandTerminalWhenActionsRun)
        XCTAssertEqual(reloadedService.current.maxTerminalSessions, 12)
    }

    func testUserDefaultsSettingsServicePersistsLastOpenThreadSelectionAcrossReloads() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)
        let container = try makeModelContainer()
        let context = ModelContext(container)
        let project = Project(path: "/tmp/\(UUID().uuidString)", name: "Fixture")
        let conversation = Conversation(title: "Main", provider: "claude")
        let thread = AgentThread(name: "Primary", project: project, conversations: [conversation])
        project.threads.append(thread)
        context.insert(project)
        try context.save()

        service.update {
            $0.reopenLastThreadAndConversationOnLaunch = true
            $0.lastOpenThreadID = thread.persistentModelID
            $0.lastOpenConversationID = conversation.persistentModelID
        }

        let reloadedService = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(reloadedService.current.lastOpenThreadID, thread.persistentModelID)
        XCTAssertEqual(reloadedService.current.lastOpenConversationID, conversation.persistentModelID)
    }

    func testUserDefaultsSettingsServiceIgnoresInvalidSavedRestoreIdentifiers() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "permissionMode": "plan",
            "effort": "high",
            "reopenLastThreadAndConversationOnLaunch": true,
            "autoTrustProjects": true,
            "createWorktreeByDefault": false,
            "theme": "dark",
            "codeFontFamily": "Monaco",
            "codeFontSize": 16,
            "chatFontSize": 18,
            "diffViewerWidth": 520,
            "notifications": [
                "enabled": true,
                "osNotifications": true,
                "sound": true,
                "soundName": "Glass"
            ],
            "branchPrefix": "feature/",
            "providerConfigs": [:],
            "lastOpenThreadID": "not-a-persistent-id",
            "lastOpenConversationID": 42
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.permissionMode, "plan")
        XCTAssertTrue(service.current.reopenLastThreadAndConversationOnLaunch)
        XCTAssertNil(service.current.lastOpenThreadID)
        XCTAssertNil(service.current.lastOpenConversationID)
    }

    func testUserDefaultsSettingsServiceLeavesCurrentUnchangedWhenEncodingFails() throws {
        enum EncodingFailure: Error {
            case example
        }

        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(
            defaults: defaults,
            encode: { _ in throw EncodingFailure.example }
        )

        service.update {
            $0.branchPrefix = "feature/"
        }

        XCTAssertEqual(service.current, AppSettings())
        XCTAssertNil(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
    }

    func testUserDefaultsSettingsServiceFallsBackToDefaultsForCorruptStoredJSON() throws {
        let defaults = try makeDefaults()
        defaults.set(Data("not-json".utf8), forKey: UserDefaultsSettingsService.storageKey)

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current, AppSettings())
    }

    func testUserDefaultsSettingsServiceMigratesLegacyAutoTrustWorktreesKey() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "autoTrustWorktrees": false
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertFalse(service.current.autoTrustProjects)
    }

    func testUserDefaultsSettingsServiceMigratesLegacyBranchPrefixSeparator() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "branchPrefix": "feature"
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.branchPrefix, "feature/")
    }

    func testUserDefaultsSettingsServicePreservesCurrentBranchPrefixLiterally() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "settingsSchemaVersion": AppSettings.currentSettingsSchemaVersion,
            "branchPrefix": "feature"
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.branchPrefix, "feature")
    }

    func testUserDefaultsSettingsServiceNormalizesInvalidStoredValuesOnLoad() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "codex",
            "permissionMode": "invalid",
            "effort": "turbo",
            "autoTrustProjects": true,
            "createWorktreeByDefault": false,
            "theme": "sepia",
            "codeFontFamily": "Monaco",
            "codeFontSize": 16,
            "chatFontSize": 18,
            "diffViewerWidth": 40,
            "notifications": [
                "enabled": true,
                "osNotifications": true,
                "sound": true,
                "soundName": "Bonk"
            ],
            "branchPrefix": "alveary/",
            "providerConfigs": [:]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.defaultProvider, "claude")
        XCTAssertEqual(service.current.permissionMode, "default")
        XCTAssertEqual(service.current.effort, AppSettings.defaultEffortLevel)
        XCTAssertEqual(service.current.theme, "system")
        XCTAssertEqual(service.current.diffViewerWidth, 320)
        XCTAssertEqual(service.current.notifications.soundName, "Glass")
    }

    func testUserDefaultsSettingsServiceUsesDefaultSplitFractionWhenStoredJSONPredatesField() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "permissionMode": "plan",
            "effort": "high",
            "autoTrustProjects": true,
            "createWorktreeByDefault": false,
            "theme": "dark",
            "codeFontFamily": "Monaco",
            "codeFontSize": 16,
            "chatFontSize": 18,
            "diffViewerWidth": 520,
            "notifications": [
                "enabled": true,
                "osNotifications": true,
                "sound": true,
                "soundName": "Glass"
            ],
            "branchPrefix": "feature/",
            "providerConfigs": [:]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.permissionMode, "plan")
        XCTAssertEqual(service.current.diffViewerWidth, 520)
        XCTAssertEqual(service.current.diffViewerTopSectionFraction, AppSettings.defaultDiffViewerTopSectionFraction)
    }

    func testUserDefaultsSettingsServiceUsesDefaultDeleteKeyActionWhenStoredJSONPredatesField() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "permissionMode": "plan",
            "effort": "high",
            "autoTrustProjects": true,
            "createWorktreeByDefault": false,
            "theme": "dark",
            "codeFontFamily": "Monaco",
            "codeFontSize": 16,
            "chatFontSize": 18,
            "diffViewerWidth": 520,
            "notifications": [
                "enabled": true,
                "osNotifications": true,
                "sound": true,
                "soundName": "Glass"
            ],
            "branchPrefix": "feature/",
            "providerConfigs": [:]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.deleteKeyAction, .archive)
    }

    func testUserDefaultsSettingsServiceUsesDefaultLaunchRestoreWhenStoredJSONPredatesField() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "permissionMode": "plan",
            "effort": "high",
            "autoTrustProjects": true,
            "createWorktreeByDefault": false,
            "theme": "dark",
            "codeFontFamily": "Monaco",
            "codeFontSize": 16,
            "chatFontSize": 18,
            "diffViewerWidth": 520,
            "notifications": [
                "enabled": true,
                "osNotifications": true,
                "sound": true,
                "soundName": "Glass"
            ],
            "branchPrefix": "feature/",
            "providerConfigs": [:]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertTrue(service.current.reopenLastThreadAndConversationOnLaunch)
    }

    func testUserDefaultsSettingsServicePreservesExplicitStoredLaunchRestoreFalse() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "reopenLastThreadAndConversationOnLaunch": false
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertFalse(service.current.reopenLastThreadAndConversationOnLaunch)
    }

    func testServicesNormalizeInvalidValuesDuringUpdate() throws {
        let defaults = try makeDefaults()
        let userDefaultsService = UserDefaultsSettingsService(defaults: defaults)
        let inMemoryService = InMemorySettingsService()

        userDefaultsService.update {
            $0.defaultProvider = "codex"
            $0.permissionMode = "invalid"
            $0.effort = "turbo"
            $0.theme = "sepia"
            $0.diffViewerWidth = 10_000
            $0.notifications.soundName = "Bonk"
        }
        inMemoryService.update {
            $0.defaultProvider = "codex"
            $0.permissionMode = "invalid"
            $0.effort = "turbo"
            $0.theme = "sepia"
            $0.diffViewerWidth = 10_000
            $0.notifications.soundName = "Bonk"
        }

        XCTAssertEqual(userDefaultsService.current.defaultProvider, "claude")
        XCTAssertEqual(userDefaultsService.current.permissionMode, "default")
        XCTAssertEqual(userDefaultsService.current.effort, AppSettings.defaultEffortLevel)
        XCTAssertEqual(userDefaultsService.current.theme, "system")
        XCTAssertEqual(userDefaultsService.current.diffViewerWidth, 960)
        XCTAssertEqual(userDefaultsService.current.notifications.soundName, "Glass")

        XCTAssertEqual(inMemoryService.current.defaultProvider, "claude")
        XCTAssertEqual(inMemoryService.current.permissionMode, "default")
        XCTAssertEqual(inMemoryService.current.effort, AppSettings.defaultEffortLevel)
        XCTAssertEqual(inMemoryService.current.theme, "system")
        XCTAssertEqual(inMemoryService.current.diffViewerWidth, 960)
        XCTAssertEqual(inMemoryService.current.notifications.soundName, "Glass")
    }

    private func makeDefaults() throws -> UserDefaults {
        let suiteName = "SettingsServiceTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        addTeardownBlock {
            defaults.removePersistentDomain(forName: suiteName)
        }
        return defaults
    }

    private func makeModelContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
