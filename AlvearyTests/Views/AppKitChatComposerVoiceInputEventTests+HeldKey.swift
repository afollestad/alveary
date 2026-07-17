@preconcurrency import AppKit
import Carbon
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatComposerVoiceInputEventTests {
    func testInitialShortcutConfigurationDoesNotForceStop() {
        let panel = AppKitChatComposerPanelView()
        var forcedStopCount = 0

        panel.configure(panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onForcedStop: { forcedStopCount += 1 }
        ))

        XCTAssertEqual(forcedStopCount, 0)
    }

    func testShortcutRebindingWithoutTrackedKeyForcesPreviousConfigurationStop() {
        let panel = AppKitChatComposerPanelView()
        var previousForcedStopCount = 0
        var nextForcedStopCount = 0
        panel.configuration = panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onForcedStop: { previousForcedStopCount += 1 }
        )

        panel.configure(panelConfiguration(
            descriptor: .controlCommandShiftSpace,
            isEnabled: true,
            onForcedStop: { nextForcedStopCount += 1 }
        ))

        XCTAssertNil(panel.trackedVoiceInputKeyCode)
        XCTAssertNil(panel.suppressedVoiceInputKeyUpCode)
        XCTAssertEqual(previousForcedStopCount, 1)
        XCTAssertEqual(nextForcedStopCount, 0)
    }

    func testBlockingOverlayForcesVoiceInputStop() {
        let panel = AppKitChatComposerPanelView()
        var forcedStopCount = 0
        panel.configure(panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onForcedStop: { forcedStopCount += 1 }
        ))

        panel.configure(panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: false,
            interactionOverlayConfiguration: makeOverlayConfiguration(id: "blocking"),
            onForcedStop: { forcedStopCount += 1 }
        ))

        XCTAssertEqual(forcedStopCount, 1)
    }

    func testRepeatedShortcutKeyDownIsConsumedWhileHeld() throws {
        let panel = AppKitChatComposerPanelView()
        panel.trackedVoiceInputKeyCode = 49
        let repeatedSpace = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: " ",
            charactersIgnoringModifiers: " ",
            isARepeat: true,
            keyCode: 49
        ))

        XCTAssertNil(panel.handleVoiceInputKeyEvent(repeatedSpace))
        XCTAssertEqual(panel.trackedVoiceInputKeyCode, 49)
    }

    func testDifferentReboundShortcutWaitsForSuppressedOldKeyUp() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let oldShortcut = PhysicalKeyboardShortcut.controlShiftSpace
        let newShortcut = PhysicalKeyboardShortcut(
            keyCode: UInt16(kVK_ANSI_D),
            modifiers: [.control, .shift],
            keyEquivalent: "D"
        )
        var pressCount = 0
        panel.configure(panelConfiguration(
            descriptor: oldShortcut,
            isEnabled: true,
            onRelease: { _ in true }
        ))
        let window = NSWindow(
            contentRect: NSRect(x: -1400, y: -1100, width: 420, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = panel
        window.makeKeyAndOrderFront(nil)
        defer { window.close() }

        panel.trackedVoiceInputKeyCode = oldShortcut.keyCode
        panel.configure(panelConfiguration(
            descriptor: newShortcut,
            isEnabled: true,
            onPress: {
                pressCount += 1
                return true
            }
        ))

        let newKeyDown = try voiceShortcutEvent(
            type: .keyDown,
            shortcut: newShortcut,
            characters: "d"
        )
        XCTAssertTrue(panel.handleVoiceInputKeyEvent(newKeyDown, keyWindow: window) === newKeyDown)
        XCTAssertEqual(pressCount, 0)
        XCTAssertNil(panel.trackedVoiceInputKeyCode)

        let oldKeyUp = try voiceShortcutEvent(
            type: .keyUp,
            shortcut: oldShortcut,
            characters: " "
        )
        XCTAssertNil(panel.handleVoiceInputKeyEvent(oldKeyUp, keyWindow: window))
        XCTAssertNil(panel.suppressedVoiceInputKeyUpCode)

        XCTAssertNil(panel.handleVoiceInputKeyEvent(newKeyDown, keyWindow: window))
        XCTAssertEqual(pressCount, 1)
        XCTAssertEqual(panel.trackedVoiceInputKeyCode, newShortcut.keyCode)
    }

    private func voiceShortcutEvent(
        type: NSEvent.EventType,
        shortcut: PhysicalKeyboardShortcut,
        characters: String
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: [.control, .shift],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: false,
            keyCode: shortcut.keyCode
        ))
    }
}
