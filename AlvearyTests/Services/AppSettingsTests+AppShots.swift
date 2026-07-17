import Carbon
import CoreGraphics
import Foundation
import XCTest

@testable import Alveary

extension AppSettingsTests {
    func testDefaultAppShotSettings() {
        let settings = AppSettings()

        XCTAssertTrue(settings.appShotsEnabled)
        XCTAssertEqual(settings.appShotShortcut, .controlShiftS)
    }

    func testDecodeDefaultsAppShotSettingsWhenFieldsAreMissing() throws {
        let json = Data("{}".utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertTrue(settings.appShotsEnabled)
        XCTAssertEqual(settings.appShotShortcut, .controlShiftS)
    }

    func testDecodePreservesAppShotSettings() throws {
        let json = Data(#"{"appShotsEnabled":false,"appShotShortcut":"commandShiftS"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertFalse(settings.appShotsEnabled)
        XCTAssertEqual(settings.appShotShortcut, .commandShiftS)
    }

    func testDecodeMigratesLegacyBothCommandAppShotShortcutToDefault() throws {
        let json = Data(#"{"appShotShortcut":"bothCommand"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.appShotShortcut, .controlShiftS)
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

    func testDecodeAndNormalizePreserveLegacyModifierKeyAppShotShortcut() throws {
        let json = Data(
            #"""
            {
              "appShotShortcut": {
                "kind": "keyChord",
                "keyChord": {
                  "keyCode": 55,
                  "modifiers": 10,
                  "keyEquivalent": "⌘"
                }
              }
            }
            """#.utf8
        )

        let settings = try JSONDecoder().decode(AppSettings.self, from: json).normalized()

        XCTAssertEqual(
            settings.appShotShortcut,
            AppShotKeyboardShortcut(
                keyCode: UInt16(kVK_Command),
                modifiers: [.control, .shift],
                keyEquivalent: "⌘"
            )
        )
    }

    func testAppShotDisplayPreservesRecordedSpaceGlyph() {
        let shortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_Space),
            modifiers: [.control, .shift],
            keyEquivalent: "␣"
        )

        XCTAssertEqual(shortcut.displayString, "⌃⇧␣")
    }

    func testDecodeDefaultsAppShotShortcutWhenFieldIsInvalid() throws {
        let json = Data(#"{"appShotShortcut":"controlOptionA"}"#.utf8)
        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.appShotShortcut, .controlShiftS)
    }

    func testNormalizeDefaultsInvalidRecordedAppShotShortcut() {
        var settings = AppSettings()
        settings.appShotShortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: .shift,
            keyEquivalent: "A"
        )

        XCTAssertEqual(settings.normalized().appShotShortcut, .controlShiftS)
    }

    func testNormalizeDefaultsSingleModifierRecordedAppShotShortcut() {
        var settings = AppSettings()
        settings.appShotShortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_A),
            modifiers: .command,
            keyEquivalent: "A"
        )

        XCTAssertEqual(settings.normalized().appShotShortcut, .controlShiftS)
    }

    func testAppShotShortcutValidationRejectsSingleModifierShortcut() {
        let shortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_R),
            modifiers: .command,
            keyEquivalent: "R"
        )

        XCTAssertEqual(
            AppShotKeyboardShortcut.validationMessage(for: shortcut, currentShortcut: .controlShiftS),
            "Use at least two modifier keys."
        )
    }

    func testAppShotShortcutValidationPreservesSystemConflictPrecedence() {
        let shortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_Space),
            modifiers: .command,
            keyEquivalent: "␣"
        )

        XCTAssertEqual(
            AppShotKeyboardShortcut.validationMessage(for: shortcut, currentShortcut: .controlShiftS),
            "⌘␣ conflicts with a macOS keyboard shortcut."
        )
    }

    func testAppShotShortcutValidationRejectsKnownMacOSShortcut() {
        let shortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_5),
            modifiers: [.command, .shift],
            keyEquivalent: "5"
        )

        XCTAssertEqual(
            AppShotKeyboardShortcut.validationMessage(for: shortcut, currentShortcut: .controlShiftS),
            "⇧⌘5 conflicts with a macOS keyboard shortcut."
        )
    }

    func testAppShotShortcutValidationRejectsKnownAppShortcut() {
        let shortcut = AppShotKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.command, .shift],
            keyEquivalent: "T"
        )

        XCTAssertEqual(
            AppShotKeyboardShortcut.validationMessage(for: shortcut, currentShortcut: .controlShiftS),
            "⇧⌘T is already used by Toggle Terminal."
        )
    }

    func testAppShotPermissionErrorsExposeRequestablePermission() {
        XCTAssertEqual(AppShotCaptureError.accessibilityPermissionMissing.missingPermission, .accessibility)
        XCTAssertEqual(AppShotCaptureError.screenRecordingPermissionMissing.missingPermission, .screenRecording)
    }

    func testAppShotNonPermissionErrorsDoNotExposeRequestablePermission() {
        XCTAssertNil(AppShotCaptureError.disabled.missingPermission)
        XCTAssertNil(AppShotCaptureError.noTargetWindow.missingPermission)
        XCTAssertNil(AppShotCaptureError.noReliableScreenCaptureMatch.missingPermission)
        XCTAssertNil(AppShotCaptureError.screenshotEncodingFailed.missingPermission)
        XCTAssertNil(AppShotCaptureError.unsupportedProvider("mock").missingPermission)
        XCTAssertNil(AppShotCaptureError.claudeScreenshotUnreadable("/tmp/appshot.png").missingPermission)
    }

    func testAppShotPermissionSnapshotUsesOverrides() {
        let snapshot = AppShotPermissionSnapshot.makeCurrent(
            accessibilityAllowed: true,
            inputMonitoringAllowed: false,
            screenRecordingAllowed: true
        )

        XCTAssertTrue(snapshot.isAllowed(.accessibility))
        XCTAssertFalse(snapshot.isAllowed(.inputMonitoring))
        XCTAssertTrue(snapshot.isAllowed(.screenRecording))
    }

    func testScreenRecordingWindowProbeAcceptsForeignWindowWithNameMetadata() {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier
        let windowInfo: [String: Any] = [
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowOwnerPID as String: NSNumber(value: currentProcessIdentifier + 1),
            kCGWindowName as String: ""
        ]

        XCTAssertTrue(AppShotPermission.hasReadableForeignWindowMetadata(windowInfo))
    }

    func testScreenRecordingWindowProbeRejectsOwnNameRedactedAndNonNormalWindows() {
        let currentProcessIdentifier = ProcessInfo.processInfo.processIdentifier

        XCTAssertFalse(AppShotPermission.hasReadableForeignWindowMetadata([
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowOwnerPID as String: NSNumber(value: currentProcessIdentifier),
            kCGWindowName as String: "Alveary"
        ]))
        XCTAssertFalse(AppShotPermission.hasReadableForeignWindowMetadata([
            kCGWindowLayer as String: NSNumber(value: 0),
            kCGWindowOwnerPID as String: NSNumber(value: currentProcessIdentifier + 1)
        ]))
        XCTAssertFalse(AppShotPermission.hasReadableForeignWindowMetadata([
            kCGWindowLayer as String: NSNumber(value: 1),
            kCGWindowOwnerPID as String: NSNumber(value: currentProcessIdentifier + 1),
            kCGWindowName as String: "System Settings"
        ]))
    }
}
