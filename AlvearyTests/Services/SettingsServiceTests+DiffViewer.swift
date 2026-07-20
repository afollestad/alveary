import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
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

        XCTAssertEqual(service.current.permissionMode, "default")
        XCTAssertEqual(service.current.diffViewerWidth, 520)
        XCTAssertEqual(service.current.skillsPaneWidth, 380)
        XCTAssertEqual(service.current.mcpPaneWidth, 380)
        XCTAssertEqual(service.current.scheduledTasksPaneWidth, 380)
        XCTAssertEqual(service.current.diffViewerTopSectionFraction, AppSettings.defaultDiffViewerTopSectionFraction)
        XCTAssertEqual(service.current.diffViewerCommitsTopSectionFraction, AppSettings.defaultDiffViewerTopSectionFraction)
    }

    func testUserDefaultsSettingsServiceUsesDefaultDiffViewerModeWhenStoredJSONPredatesField() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "diffViewerWidth": 520
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertEqual(service.current.diffViewerMode, AppSettings.defaultDiffViewerMode)
    }

    func testRightPaneWidthsRoundTripAndClampIndependently() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update {
            $0.diffViewerWidth = 410
            $0.skillsPaneWidth = 100
            $0.mcpPaneWidth = 640
            $0.scheduledTasksPaneWidth = 2_000
        }

        XCTAssertEqual(service.current.diffViewerWidth, 410)
        XCTAssertEqual(service.current.skillsPaneWidth, 320)
        XCTAssertEqual(service.current.mcpPaneWidth, 640)
        XCTAssertEqual(service.current.scheduledTasksPaneWidth, 960)

        let reloaded = UserDefaultsSettingsService(defaults: defaults)
        XCTAssertEqual(reloaded.current.diffViewerWidth, 410)
        XCTAssertEqual(reloaded.current.skillsPaneWidth, 320)
        XCTAssertEqual(reloaded.current.mcpPaneWidth, 640)
        XCTAssertEqual(reloaded.current.scheduledTasksPaneWidth, 960)
    }

    func testUpdatingOneContextualPaneWidthLeavesOtherWidthsUnchanged() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update { $0.skillsPaneWidth = 512 }

        XCTAssertEqual(service.current.skillsPaneWidth, 512)
        XCTAssertEqual(service.current.diffViewerWidth, 380)
        XCTAssertEqual(service.current.mcpPaneWidth, 380)
        XCTAssertEqual(service.current.scheduledTasksPaneWidth, 380)
    }
}
