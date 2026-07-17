@preconcurrency import AppKit
import Carbon
import XCTest

@testable import Alveary

@MainActor
final class PhysicalKeyboardShortcutRecorderTests: XCTestCase {
    func testRecorderPublishesOneImmutablePhysicalDescriptor() throws {
        let button = PhysicalShortcutRecorderButtonView()
        var recordedShortcut: PhysicalKeyboardShortcut?
        button.validate = { _ in nil }
        button.onShortcutRecorded = { recordedShortcut = $0 }

        button.performClick(nil)
        button.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_ANSI_R),
            modifiers: [.command, .control],
            characters: "r"
        ))

        XCTAssertFalse(button.isRecording)
        XCTAssertEqual(
            recordedShortcut,
            PhysicalKeyboardShortcut(
                keyCode: UInt16(kVK_ANSI_R),
                modifiers: [.command, .control],
                keyEquivalent: "R"
            )
        )
        XCTAssertEqual(recordedShortcut?.displayString, "⌃⌘R")
    }

    func testUnmodifiedEscapeCancelsRecordingWithoutPublishing() throws {
        let button = PhysicalShortcutRecorderButtonView()
        var didRecord = false
        button.onShortcutRecorded = { _ in didRecord = true }

        button.performClick(nil)
        button.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Escape),
            modifiers: [],
            characters: "\u{1b}"
        ))

        XCTAssertFalse(button.isRecording)
        XCTAssertFalse(didRecord)
    }

    func testAppShotRecorderCanPreserveLegacyModifierKeyRecordingBehavior() throws {
        let button = PhysicalShortcutRecorderButtonView()
        button.allowsModifierKey = true
        var recordedShortcut: PhysicalKeyboardShortcut?
        button.validate = { _ in nil }
        button.onShortcutRecorded = { recordedShortcut = $0 }

        button.performClick(nil)
        button.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Command),
            modifiers: [.control, .shift],
            characters: ""
        ))

        XCTAssertEqual(
            recordedShortcut,
            PhysicalKeyboardShortcut(
                keyCode: UInt16(kVK_Command),
                modifiers: [.control, .shift],
                keyEquivalent: "⌘"
            )
        )
    }

    func testAppShotRecorderImmediatelyUsesLegacySpaceDisplay() throws {
        let button = PhysicalShortcutRecorderButtonView()
        button.allowsModifierKey = true
        button.recordedShortcutDisplay = { AppShotKeyboardShortcut(keyChord: $0).displayString }
        button.validate = { _ in nil }

        button.performClick(nil)
        button.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_Space),
            modifiers: [.control, .shift],
            characters: " "
        ))

        XCTAssertEqual(button.title, "⌃⇧␣")
        XCTAssertEqual(button.accessibilityValue() as? String, "⌃⇧␣")
    }

    func testAppShotRecorderPreservesLegacyInvalidInputMessage() throws {
        let button = PhysicalShortcutRecorderButtonView()
        button.allowsModifierKey = true
        button.invalidShortcutMessage = "Use at least two modifier keys."
        var validationMessage: String?
        button.onValidationError = { validationMessage = $0 }

        button.performClick(nil)
        button.keyDown(with: try keyEvent(
            keyCode: UInt16(kVK_ANSI_R),
            modifiers: [],
            characters: "r"
        ))

        XCTAssertEqual(validationMessage, "Use at least two modifier keys.")
        XCTAssertTrue(button.isRecording)
    }

    private func keyEvent(
        keyCode: UInt16,
        modifiers: NSEvent.ModifierFlags,
        characters: String
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: keyCode
        ))
    }
}
