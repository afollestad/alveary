import Foundation
import XCTest

@testable import Alveary

@MainActor
extension SettingsServiceTests {
    func testUserDefaultsSettingsServiceUsesDefaultContextManagementWhenStoredJSONPredatesFields() throws {
        let defaults = try makeDefaults()
        let payload: [String: Any] = [
            "defaultProvider": "claude",
            "permissionMode": "plan",
            "effort": "high",
            "providerConfigs": [:]
        ]
        defaults.set(
            try JSONSerialization.data(withJSONObject: payload),
            forKey: UserDefaultsSettingsService.storageKey
        )

        let service = UserDefaultsSettingsService(defaults: defaults)

        XCTAssertTrue(service.current.contextManagementEnabled)
        XCTAssertEqual(
            service.current.sessionHandoffWindowPercentage,
            AppSettings.defaultSessionHandoffWindowPercentage
        )
        XCTAssertTrue(service.current.handoffSteeringEnabled)
        XCTAssertEqual(
            service.current.handoffSteeringCountdownSeconds,
            AppSettings.defaultHandoffSteeringCountdownSeconds
        )
        XCTAssertEqual(
            service.current.handoffPromptSendCountdownSeconds,
            AppSettings.defaultHandoffPromptSendCountdownSeconds
        )
        XCTAssertTrue(service.current.handoffContextCustomizationEnabled)
        XCTAssertEqual(service.current.sessionHandoffPrompt, AppSettings.defaultSessionHandoffPrompt)
    }

    func testServicesNormalizeInvalidHandoffCountdownValuesDuringUpdate() throws {
        let defaults = try makeDefaults()
        let userDefaultsService = UserDefaultsSettingsService(defaults: defaults)
        let inMemoryService = InMemorySettingsService()

        userDefaultsService.update {
            $0.handoffSteeringCountdownSeconds = 1
            $0.handoffPromptSendCountdownSeconds = -1
        }
        inMemoryService.update {
            $0.handoffSteeringCountdownSeconds = 500
            $0.handoffPromptSendCountdownSeconds = 500
        }

        XCTAssertEqual(
            userDefaultsService.current.handoffSteeringCountdownSeconds,
            AppSettings.supportedHandoffSteeringCountdownRange.lowerBound
        )
        XCTAssertEqual(
            userDefaultsService.current.handoffPromptSendCountdownSeconds,
            AppSettings.supportedHandoffPromptSendCountdownRange.lowerBound
        )
        XCTAssertEqual(
            inMemoryService.current.handoffSteeringCountdownSeconds,
            AppSettings.supportedHandoffSteeringCountdownRange.upperBound
        )
        XCTAssertEqual(
            inMemoryService.current.handoffPromptSendCountdownSeconds,
            AppSettings.supportedHandoffPromptSendCountdownRange.upperBound
        )
    }
}
