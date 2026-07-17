import Carbon
import Foundation
import XCTest

@testable import Alveary

extension AppSettingsTests {
    func testDefaultVoiceInputShortcutUsesControlShiftSpace() {
        let shortcut = AppSettings().voiceInputShortcut

        XCTAssertEqual(shortcut, .controlShiftSpace)
        XCTAssertEqual(shortcut?.displayString, "⌃⇧Space")
    }

    func testAppShotLegacyShortcutSerializationIsUnchanged() throws {
        let controlShiftData = try JSONEncoder().encode(AppShotKeyboardShortcut.controlShiftS)
        let bothCommandData = try JSONEncoder().encode(AppShotKeyboardShortcut.bothCommand)
        let customData = try JSONEncoder().encode(
            AppShotKeyboardShortcut(
                keyCode: UInt16(kVK_ANSI_A),
                modifiers: [.command, .option],
                keyEquivalent: "A"
            )
        )
        let customJSON = try XCTUnwrap(JSONSerialization.jsonObject(with: customData) as? [String: Any])
        let keyChord = try XCTUnwrap(customJSON["keyChord"] as? [String: Any])

        XCTAssertEqual(String(data: controlShiftData, encoding: .utf8), #""controlShiftS""#)
        XCTAssertEqual(String(data: bothCommandData, encoding: .utf8), #""bothCommand""#)
        XCTAssertEqual(customJSON["kind"] as? String, "keyChord")
        XCTAssertEqual(keyChord["keyCode"] as? Int, Int(kVK_ANSI_A))
        XCTAssertEqual(keyChord["modifiers"] as? Int, 5)
        XCTAssertEqual(keyChord["keyEquivalent"] as? String, "A")
    }

    func testVoiceInputMigrationUsesFallbackWhenPrimaryConflictsWithAppShot() {
        let appShotShortcut = AppShotKeyboardShortcut(keyChord: .controlShiftSpace)

        XCTAssertEqual(
            AppSettings.migratedVoiceInputShortcut(
                appShotShortcut: appShotShortcut,
                hasEnabledSystemConflict: { _ in false }
            ),
            .controlCommandShiftSpace
        )
    }

    func testVoiceInputMigrationUsesFallbackWhenPrimaryConflictsWithMacOS() {
        XCTAssertEqual(
            AppSettings.migratedVoiceInputShortcut(
                appShotShortcut: .controlShiftS,
                hasEnabledSystemConflict: { $0 == .controlShiftSpace }
            ),
            .controlCommandShiftSpace
        )
    }

    func testVoiceInputMigrationLeavesKeyboardUnavailableWhenBothDefaultsConflict() {
        XCTAssertNil(
            AppSettings.migratedVoiceInputShortcut(
                appShotShortcut: .controlShiftS,
                hasEnabledSystemConflict: { shortcut in
                    shortcut == .controlShiftSpace || shortcut == .controlCommandShiftSpace
                }
            )
        )
    }

    func testDecodePreservesStoredVoiceInputShortcutWithoutSilentlyReplacingConflict() throws {
        let json = Data(
            #"""
            {
              "appShotShortcut": {
                "kind": "keyChord",
                "keyChord": { "keyCode": 49, "modifiers": 10, "keyEquivalent": "Space" }
              },
              "voiceInputShortcut": { "keyCode": 49, "modifiers": 10, "keyEquivalent": "Space" },
              "voiceInputShortcutMigrationCompleted": true
            }
            """#.utf8
        )

        let settings = try JSONDecoder().decode(AppSettings.self, from: json)

        XCTAssertEqual(settings.appShotShortcut.keyChord, .controlShiftSpace)
        XCTAssertEqual(settings.voiceInputShortcut, .controlShiftSpace)
    }

    func testExplicitUnavailableVoiceInputShortcutSurvivesRoundTrip() throws {
        var settings = AppSettings()
        settings.voiceInputShortcut = nil

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertNil(decoded.voiceInputShortcut)
        XCTAssertTrue(String(data: data, encoding: .utf8)?.contains("voiceInputShortcutMigrationCompleted") == true)
    }

    func testNormalizeInvalidVoiceInputShortcutDoesNotSilentlyChooseReplacement() {
        var settings = AppSettings()
        settings.voiceInputShortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_Command),
            modifiers: [.control, .shift],
            keyEquivalent: "⌘"
        )

        XCTAssertNil(settings.normalized().voiceInputShortcut)
    }

    func testVoiceInputShortcutValidationRejectsModifierKey() {
        let shortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_Command),
            modifiers: [.control, .shift],
            keyEquivalent: "⌘"
        )

        XCTAssertEqual(
            PhysicalKeyboardShortcutValidation.message(
                for: shortcut,
                assignment: .voiceInput,
                appShotShortcut: nil,
                voiceInputShortcut: nil,
                hasEnabledSystemConflict: { _ in false }
            ),
            "Use a nonmodifier key."
        )
    }

    func testVoiceInputAvailabilityRejectsAppShotConflictWithoutReplacingStoredShortcut() {
        var settings = AppSettings()
        settings.appShotShortcut = AppShotKeyboardShortcut(keyChord: .controlShiftSpace)
        settings.voiceInputShortcut = .controlShiftSpace

        let availability = settings.voiceInputShortcutAvailability(
            supportsVoiceInput: true,
            hasEnabledSystemConflict: { _ in false }
        )

        XCTAssertEqual(
            availability,
            .unavailable(.conflict("⌃⇧Space is already used by App Shots."))
        )
        XCTAssertEqual(settings.voiceInputShortcut, .controlShiftSpace)
    }

    func testVoiceInputAvailabilityRevalidatesExternalConflictWithoutMutatingSettings() {
        let settings = AppSettings()

        XCTAssertEqual(
            settings.voiceInputShortcutAvailability(
                supportsVoiceInput: true,
                hasEnabledSystemConflict: { _ in false }
            ).descriptor,
            .controlShiftSpace
        )
        XCTAssertEqual(
            settings.voiceInputShortcutAvailability(
                supportsVoiceInput: true,
                hasEnabledSystemConflict: { _ in true }
            ),
            .unavailable(.conflict("⌃⇧Space conflicts with a macOS keyboard shortcut."))
        )
        XCTAssertEqual(settings.voiceInputShortcut, .controlShiftSpace)
    }

    func testVoiceInputAvailabilityIsDisabledOnIntelPresentation() {
        XCTAssertEqual(
            AppSettings().voiceInputShortcutAvailability(
                supportsVoiceInput: false,
                hasEnabledSystemConflict: { _ in false }
            ),
            .unavailable(.unsupportedArchitecture)
        )
    }

    func testVoiceInputShortcutValidationRejectsEscape() {
        let shortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_Escape),
            modifiers: [.control, .shift],
            keyEquivalent: "⎋"
        )

        XCTAssertEqual(
            PhysicalKeyboardShortcutValidation.message(
                for: shortcut,
                assignment: .voiceInput,
                appShotShortcut: nil,
                voiceInputShortcut: nil,
                hasEnabledSystemConflict: { _ in false }
            ),
            "Escape is reserved for canceling actions."
        )
    }

    func testAppShotShortcutValidationPreservesModifiedEscape() {
        let shortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_Escape),
            modifiers: [.control, .shift],
            keyEquivalent: "⎋"
        )

        XCTAssertNil(PhysicalKeyboardShortcutValidation.message(
            for: shortcut,
            assignment: .appShot,
            appShotShortcut: shortcut,
            voiceInputShortcut: nil,
            hasEnabledSystemConflict: { _ in false }
        ))
    }

    func testVoiceInputShortcutValidationRejectsAlvearyShortcut() {
        let shortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.command, .shift],
            keyEquivalent: "T"
        )

        XCTAssertEqual(
            PhysicalKeyboardShortcutValidation.message(
                for: shortcut,
                assignment: .voiceInput,
                appShotShortcut: nil,
                voiceInputShortcut: nil,
                hasEnabledSystemConflict: { _ in false }
            ),
            "⇧⌘T is already used by Toggle Terminal."
        )
    }

    func testVoiceInputShortcutValidationRejectsNativeMenuShortcuts() {
        for (shortcut, expectedMessage) in nativeMenuVoiceInputShortcutCases {
            XCTAssertEqual(
                PhysicalKeyboardShortcutValidation.message(
                    for: shortcut,
                    assignment: .voiceInput,
                    appShotShortcut: nil,
                    voiceInputShortcut: nil,
                    hasEnabledSystemConflict: { _ in false }
                ),
                expectedMessage
            )
        }
    }

    func testAppShotShortcutValidationRejectsVoiceInputShortcut() {
        let shortcut = AppShotKeyboardShortcut(keyChord: .controlShiftSpace)

        XCTAssertEqual(
            AppShotKeyboardShortcut.validationMessage(
                for: shortcut,
                currentShortcut: .controlShiftS,
                voiceInputShortcut: .controlShiftSpace
            ),
            "⌃⇧Space is already used by Voice Input."
        )
    }

    func testPhysicalShortcutMatchesExactKeyDownAndKeyCodeOnlyRelease() {
        let capturedShortcut = PhysicalKeyboardShortcut.controlShiftSpace

        XCTAssertTrue(
            capturedShortcut.matches(
                keyCode: UInt16(kVK_Space),
                modifiers: [.control, .shift]
            )
        )
        XCTAssertFalse(
            capturedShortcut.matches(
                keyCode: UInt16(kVK_Space),
                modifiers: [.command, .control, .shift]
            )
        )
        XCTAssertTrue(capturedShortcut.matchesRelease(keyCode: UInt16(kVK_Space)))
        XCTAssertFalse(capturedShortcut.matchesRelease(keyCode: UInt16(kVK_ANSI_S)))
    }

    func testCapturedPhysicalDescriptorRemainsStableAcrossRebinding() {
        var settings = AppSettings()
        let capturedShortcut = settings.voiceInputShortcutAvailability(
            supportsVoiceInput: true,
            hasEnabledSystemConflict: { _ in false }
        ).descriptor

        settings.voiceInputShortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_R),
            modifiers: [.command, .control],
            keyEquivalent: "R"
        )

        XCTAssertEqual(capturedShortcut, .controlShiftSpace)
        XCTAssertTrue(capturedShortcut?.matchesRelease(keyCode: UInt16(kVK_Space)) == true)
        XCTAssertEqual(settings.voiceInputShortcut?.displayString, "⌃⌘R")
    }
}

private let nativeMenuVoiceInputShortcutCases: [(PhysicalKeyboardShortcut, String)] = [
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_H),
            modifiers: [.command, .option],
            keyEquivalent: "H"
        ),
        "⌥⌘H is already used by Hide Others."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_M),
            modifiers: [.command, .option],
            keyEquivalent: "M"
        ),
        "⌥⌘M is already used by Minimize All."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_W),
            modifiers: [.command, .option],
            keyEquivalent: "W"
        ),
        "⌥⌘W is already used by Close All."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_V),
            modifiers: [.command, .option, .shift],
            keyEquivalent: "V"
        ),
        "⌥⇧⌘V is already used by Paste and Match Style."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_T),
            modifiers: [.command, .option],
            keyEquivalent: "T"
        ),
        "⌥⌘T is already used by Show or Hide Toolbar."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_S),
            modifiers: [.command, .control],
            keyEquivalent: "S"
        ),
        "⌃⌘S is already used by Show or Hide Sidebar."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_F),
            modifiers: [.command, .control],
            keyEquivalent: "F"
        ),
        "⌃⌘F is already used by Full Screen."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_G),
            modifiers: [.command, .shift],
            keyEquivalent: "G"
        ),
        "⇧⌘G is already used by Find Previous."
    ),
    (
        PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_Slash),
            modifiers: [.command, .shift],
            keyEquivalent: "/"
        ),
        "⇧⌘/ is already used by Help."
    )
]
