import Carbon
import Foundation
import XCTest

@testable import Alveary

extension AppSettingsTests {
    func testDefaultAppShotSettings() {
        let settings = AppSettings()

        XCTAssertTrue(settings.appShotsEnabled)
        XCTAssertEqual(settings.appShotShortcut, .bothCommand)
    }

    func testDecodeDefaultsAppShotSettingsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertTrue(settings.appShotsEnabled)
        XCTAssertEqual(settings.appShotShortcut, .bothCommand)
    }

    func testDecodePreservesAppShotSettings() throws {
        let json = Data(#"{"appShotsEnabled":false,"appShotShortcut":"commandShiftS"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertFalse(settings.appShotsEnabled)
        XCTAssertEqual(settings.appShotShortcut, .commandShiftS)
    }

    func testDecodePreservesRecordedAppShotShortcut() throws {
        let json = Data(
            #"""
            {
              "appShotShortcut": {
                "kind": "keyChord",
                "keyChord": {
                  "keyCode": 0,
                  "modifiers": 5,
                  "keyEquivalent": "A"
                }
              }
            }
            """#.utf8
        )
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(
            settings.appShotShortcut,
            AppShotKeyboardShortcut(
                keyCode: UInt16(kVK_ANSI_A),
                modifiers: [.command, .option],
                keyEquivalent: "A"
            )
        )
    }

    func testDecodeDefaultsAppShotShortcutWhenFieldIsInvalid() throws {
        let json = Data(#"{"appShotShortcut":"controlOptionA"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.appShotShortcut, .bothCommand)
    }

    func testNormalizeDefaultsInvalidRecordedAppShotShortcut() {
        var settings = AppSettings()
        settings.appShotShortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: .shift,
            keyEquivalent: "A"
        )

        XCTAssertEqual(settings.normalized().appShotShortcut, .bothCommand)
    }

    func testAppShotShortcutValidationRejectsKnownAppShortcut() {
        let shortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: .command,
            keyEquivalent: "T"
        )

        XCTAssertEqual(
            AppShotKeyboardShortcut.validationMessage(for: shortcut, currentShortcut: .bothCommand),
            "⌘T is already used by New Conversation."
        )
    }
}
