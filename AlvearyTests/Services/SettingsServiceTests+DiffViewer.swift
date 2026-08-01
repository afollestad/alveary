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
        XCTAssertEqual(service.current.rightPaneWidth, 520)
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

    func testRightPaneWidthRoundTripsAndClamps() throws {
        let defaults = try makeDefaults()
        let service = UserDefaultsSettingsService(defaults: defaults)

        service.update { $0.rightPaneWidth = 410 }
        XCTAssertEqual(service.current.rightPaneWidth, 410)
        XCTAssertEqual(UserDefaultsSettingsService(defaults: defaults).current.rightPaneWidth, 410)

        service.update { $0.rightPaneWidth = 100 }
        XCTAssertEqual(service.current.rightPaneWidth, AppSettings.supportedRightPaneWidthRange.lowerBound)

        service.update { $0.rightPaneWidth = 2_000 }
        XCTAssertEqual(service.current.rightPaneWidth, AppSettings.supportedRightPaneWidthRange.upperBound)
    }

    /// The lane used to persist a width per destination, which resized the main
    /// pane whenever it switched panes. Stored per-destination widths collapse
    /// onto the Diff Viewer's, the one users sized most often.
    func testRetiredPerDestinationWidthsMigrateFromTheDiffViewerWidth() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "diffViewerWidth": 520,
            "skillsPaneWidth": 400,
            "mcpPaneWidth": 420,
            "scheduledTasksPaneWidth": 440,
            "pullRequestsPaneWidth": 460
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)
        XCTAssertEqual(service.current.rightPaneWidth, 520)

        // Re-encoding drops the retired keys, so a later launch reads the shared one.
        service.update { $0.rightPaneWidth = 500 }
        let stored = try XCTUnwrap(defaults.data(forKey: UserDefaultsSettingsService.storageKey))
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: stored) as? [String: Any])
        XCTAssertEqual(object["rightPaneWidth"] as? Double, 500)
        XCTAssertNil(object["diffViewerWidth"])
        XCTAssertNil(object["pullRequestsPaneWidth"])
    }

    /// A newer explicit value wins over a stale retired key left in the payload.
    func testSharedRightPaneWidthWinsOverTheRetiredDiffViewerWidth() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "rightPaneWidth": 600,
            "diffViewerWidth": 520
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        XCTAssertEqual(UserDefaultsSettingsService(defaults: defaults).current.rightPaneWidth, 600)
    }
}
