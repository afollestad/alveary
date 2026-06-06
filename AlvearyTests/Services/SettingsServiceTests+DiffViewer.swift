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
}
