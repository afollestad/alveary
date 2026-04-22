import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class KeyboardShortcutDisplayStringTests: XCTestCase {
    func testRendersModifiersInControlOptionShiftCommandOrder() {
        let shortcut = KeyboardShortcut("a", modifiers: [.command, .shift, .option, .control])
        XCTAssertEqual(shortcut.displayString, "⌃⌥⇧⌘A")
    }

    func testUppercasesLetterKey() {
        XCTAssertEqual(KeyboardShortcut("d", modifiers: [.shift, .command]).displayString, "⇧⌘D")
    }

    func testRendersDigitKey() {
        XCTAssertEqual(KeyboardShortcut("1", modifiers: .command).displayString, "⌘1")
    }

    func testOmitsUnusedModifiers() {
        XCTAssertEqual(KeyboardShortcut("s", modifiers: .command).displayString, "⌘S")
    }

    func testMapsSpecialKeysToGlyphs() {
        XCTAssertEqual(KeyboardShortcut(.return, modifiers: .command).displayString, "⌘↩")
        XCTAssertEqual(KeyboardShortcut(.escape, modifiers: []).displayString, "⎋")
        XCTAssertEqual(KeyboardShortcut(.tab, modifiers: []).displayString, "⇥")
        XCTAssertEqual(KeyboardShortcut(.space, modifiers: []).displayString, "␣")
        XCTAssertEqual(KeyboardShortcut(.delete, modifiers: []).displayString, "⌫")
        XCTAssertEqual(KeyboardShortcut(.deleteForward, modifiers: []).displayString, "⌦")
        XCTAssertEqual(KeyboardShortcut(.upArrow, modifiers: []).displayString, "↑")
        XCTAssertEqual(KeyboardShortcut(.downArrow, modifiers: []).displayString, "↓")
        XCTAssertEqual(KeyboardShortcut(.leftArrow, modifiers: []).displayString, "←")
        XCTAssertEqual(KeyboardShortcut(.rightArrow, modifiers: []).displayString, "→")
        XCTAssertEqual(KeyboardShortcut(.home, modifiers: []).displayString, "↖")
        XCTAssertEqual(KeyboardShortcut(.end, modifiers: []).displayString, "↘")
        XCTAssertEqual(KeyboardShortcut(.pageUp, modifiers: []).displayString, "⇞")
        XCTAssertEqual(KeyboardShortcut(.pageDown, modifiers: []).displayString, "⇟")
        XCTAssertEqual(KeyboardShortcut(.clear, modifiers: []).displayString, "⌧")
    }

    func testAddProjectConstantMatches() {
        XCTAssertEqual(KeyboardShortcut.addProject.displayString, "⌘O")
    }

    func testNewThreadConstantMatches() {
        XCTAssertEqual(KeyboardShortcut.newThread.displayString, "⌘N")
    }

    func testNewConversationConstantMatches() {
        XCTAssertEqual(KeyboardShortcut.newConversation.displayString, "⌘T")
    }

    func testCloseConversationConstantMatches() {
        XCTAssertEqual(KeyboardShortcut.closeConversation.displayString, "⌘W")
    }

    func testSettingsConstantMatches() {
        XCTAssertEqual(KeyboardShortcut.settings.displayString, "⌘,")
    }

    func testToggleDiffViewerConstantMatches() {
        XCTAssertEqual(KeyboardShortcut.toggleDiffViewer.displayString, "⇧⌘D")
    }

    func testToggleTerminalPaneConstantMatches() {
        XCTAssertEqual(KeyboardShortcut.toggleTerminalPane.displayString, "⇧⌘T")
    }
}
