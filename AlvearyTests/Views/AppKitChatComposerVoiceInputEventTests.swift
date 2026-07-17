@preconcurrency import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class AppKitChatComposerVoiceInputEventTests: XCTestCase {
    func testEscapeIsConsumedBeforeNonEditorResponderBehavior() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let window = mountedWindow(for: panel)
        defer { window.close() }
        var escapeCount = 0
        panel.configuration = panelConfiguration(onEscape: {
            escapeCount += 1
            return true
        })
        let escape = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: "\u{1b}",
            charactersIgnoringModifiers: "\u{1b}",
            isARepeat: false,
            keyCode: 53
        ))

        XCTAssertNil(panel.handleVoiceInputKeyEvent(escape, keyWindow: window))
        XCTAssertEqual(escapeCount, 1)
    }

    func testEscapeIsNotConsumedOutsideTheActiveComposerWindow() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let composerWindow = mountedWindow(for: panel)
        let otherWindow = NSWindow(
            contentRect: NSRect(x: -1200, y: -1000, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        otherWindow.isReleasedWhenClosed = false
        defer {
            otherWindow.close()
            composerWindow.close()
        }
        var escapeCount = 0
        panel.configuration = panelConfiguration(onEscape: {
            escapeCount += 1
            return true
        })
        let escape = try keyEvent(keyCode: 53, characters: "\u{1b}")

        XCTAssertTrue(panel.handleVoiceInputKeyEvent(escape, keyWindow: otherWindow) === escape)
        XCTAssertEqual(escapeCount, 0)
    }

    func testEscapeRemainsAvailableThroughBlockingComposerOverlay() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let window = mountedWindow(for: panel)
        defer { window.close() }
        var escapeCount = 0
        panel.configuration = panelConfiguration(
            interactionOverlayConfiguration: makeOverlayConfiguration(id: "blocking"),
            onEscape: {
                escapeCount += 1
                return true
            }
        )
        let escape = try keyEvent(keyCode: 53, characters: "\u{1b}")

        XCTAssertFalse(panel.canHandleVoiceInputShortcut(keyWindow: window))
        XCTAssertNil(panel.handleVoiceInputKeyEvent(escape, keyWindow: window))
        XCTAssertEqual(escapeCount, 1)
    }

    func testHandledEscapeIsSuppressedUntilMatchingKeyUp() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let window = mountedWindow(for: panel)
        defer { window.close() }
        var escapeCount = 0
        panel.configuration = panelConfiguration(onEscape: {
            escapeCount += 1
            return escapeCount == 1
        })
        let initialKeyDown = try keyEvent(keyCode: 53, characters: "\u{1b}")
        let repeatedKeyDown = try keyEvent(
            keyCode: 53,
            characters: "\u{1b}",
            isARepeat: true
        )
        let keyUp = try keyEvent(type: .keyUp, keyCode: 53, characters: "\u{1b}")
        let nextKeyDown = try keyEvent(keyCode: 53, characters: "\u{1b}")

        XCTAssertNil(panel.handleVoiceInputKeyEvent(initialKeyDown, keyWindow: window))
        XCTAssertNil(panel.handleVoiceInputKeyEvent(repeatedKeyDown, keyWindow: window))
        XCTAssertNil(panel.handleVoiceInputKeyEvent(keyUp, keyWindow: window))
        XCTAssertTrue(panel.handleVoiceInputKeyEvent(nextKeyDown, keyWindow: window) === nextKeyDown)
        XCTAssertEqual(escapeCount, 2)
    }

    func testFreshKeyDownAfterLostKeyUpForcesStopAndSuppressesItsRelease() throws {
        let panel = AppKitChatComposerPanelView()
        var forcedReleaseCount = 0
        var forcedStopCount = 0
        panel.configuration = panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onRelease: { forced in
                forcedReleaseCount += forced ? 1 : 100
                return true
            },
            onForcedStop: { forcedStopCount += 1 }
        )
        panel.trackedVoiceInputKeyCode = PhysicalKeyboardShortcut.controlShiftSpace.keyCode
        let freshKeyDown = try keyEvent(
            keyCode: PhysicalKeyboardShortcut.controlShiftSpace.keyCode,
            characters: " ",
            modifiers: [.control, .shift]
        )
        let trailingKeyUp = try keyEvent(
            type: .keyUp,
            keyCode: PhysicalKeyboardShortcut.controlShiftSpace.keyCode,
            characters: " ",
            modifiers: [.control, .shift]
        )

        XCTAssertNil(panel.handleVoiceInputKeyEvent(freshKeyDown))
        XCTAssertNil(panel.trackedVoiceInputKeyCode)
        XCTAssertEqual(panel.suppressedVoiceInputKeyUpCode, PhysicalKeyboardShortcut.controlShiftSpace.keyCode)
        XCTAssertEqual(forcedReleaseCount, 1)
        XCTAssertEqual(forcedStopCount, 1)

        XCTAssertNil(panel.handleVoiceInputKeyEvent(trailingKeyUp))
        XCTAssertNil(panel.suppressedVoiceInputKeyUpCode)
        XCTAssertEqual(forcedReleaseCount, 1)
    }

    func testTransientPhaseDisableDoesNotForceReleaseHeldShortcut() {
        let panel = AppKitChatComposerPanelView()
        var releaseCount = 0
        var forcedStopCount = 0
        panel.configuration = panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onRelease: { _ in
                releaseCount += 1
                return true
            },
            onForcedStop: { forcedStopCount += 1 }
        )
        panel.trackedVoiceInputKeyCode = PhysicalKeyboardShortcut.controlShiftSpace.keyCode
        let next = shortcutConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: false,
            onRelease: { _ in
                releaseCount += 1
                return true
            },
            onForcedStop: { forcedStopCount += 1 }
        )

        panel.reconcileHeldVoiceShortcut(next: next)

        XCTAssertEqual(panel.trackedVoiceInputKeyCode, PhysicalKeyboardShortcut.controlShiftSpace.keyCode)
        XCTAssertEqual(releaseCount, 0)
        XCTAssertEqual(forcedStopCount, 0)
    }

    func testHeldShortcutRebindingForcesReleaseAndSuppressesOldKeyUp() throws {
        let panel = AppKitChatComposerPanelView()
        var forcedReleaseCount = 0
        var previousForcedStopCount = 0
        var nextForcedStopCount = 0
        panel.configuration = panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onRelease: { forced in
                forcedReleaseCount += forced ? 1 : 100
                return true
            },
            onForcedStop: { previousForcedStopCount += 1 }
        )
        panel.trackedVoiceInputKeyCode = PhysicalKeyboardShortcut.controlShiftSpace.keyCode
        let next = shortcutConfiguration(
            descriptor: .controlCommandShiftSpace,
            isEnabled: true,
            onRelease: { _ in false },
            onForcedStop: { nextForcedStopCount += 1 }
        )
        let trailingKeyUp = try keyEvent(
            type: .keyUp,
            keyCode: PhysicalKeyboardShortcut.controlShiftSpace.keyCode,
            characters: " ",
            modifiers: [.control, .shift]
        )

        panel.reconcileHeldVoiceShortcut(next: next)

        XCTAssertNil(panel.trackedVoiceInputKeyCode)
        XCTAssertEqual(panel.suppressedVoiceInputKeyUpCode, PhysicalKeyboardShortcut.controlShiftSpace.keyCode)
        XCTAssertEqual(forcedReleaseCount, 1)
        XCTAssertEqual(previousForcedStopCount, 1)
        XCTAssertEqual(nextForcedStopCount, 0)
        XCTAssertNil(panel.handleVoiceInputKeyEvent(trailingKeyUp))
        XCTAssertNil(panel.suppressedVoiceInputKeyUpCode)
        XCTAssertEqual(forcedReleaseCount, 1)
    }

    func testForcedLifecycleReleaseSuppressesTrailingKeyUpAndAllowsFreshPress() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        let window = mountedWindow(for: panel)
        defer { window.close() }
        var pressCount = 0
        var releaseCount = 0
        var forcedStopCount = 0
        panel.configuration = panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onPress: {
                pressCount += 1
                return true
            },
            onRelease: { forced in
                releaseCount += forced ? 1 : 100
                return true
            },
            onForcedStop: { forcedStopCount += 1 }
        )
        panel.trackedVoiceInputKeyCode = PhysicalKeyboardShortcut.controlShiftSpace.keyCode
        let shortcutKeyUp = try keyEvent(
            type: .keyUp,
            keyCode: PhysicalKeyboardShortcut.controlShiftSpace.keyCode,
            characters: " ",
            modifiers: [.control, .shift]
        )
        let freshKeyDown = try keyEvent(
            keyCode: PhysicalKeyboardShortcut.controlShiftSpace.keyCode,
            characters: " ",
            modifiers: [.control, .shift]
        )

        panel.forceVoiceInputReleaseAndStop()
        panel.forceVoiceInputReleaseAndStop()

        XCTAssertNil(panel.trackedVoiceInputKeyCode)
        XCTAssertEqual(panel.suppressedVoiceInputKeyUpCode, PhysicalKeyboardShortcut.controlShiftSpace.keyCode)
        XCTAssertEqual(releaseCount, 1)
        XCTAssertEqual(forcedStopCount, 2)
        XCTAssertNil(panel.handleVoiceInputKeyEvent(shortcutKeyUp, keyWindow: window))
        XCTAssertNil(panel.suppressedVoiceInputKeyUpCode)

        panel.trackedVoiceInputKeyCode = PhysicalKeyboardShortcut.controlShiftSpace.keyCode
        panel.forceVoiceInputReleaseAndStop()

        XCTAssertNil(panel.handleVoiceInputKeyEvent(freshKeyDown, keyWindow: window))
        XCTAssertNil(panel.suppressedVoiceInputKeyUpCode)
        XCTAssertEqual(panel.trackedVoiceInputKeyCode, PhysicalKeyboardShortcut.controlShiftSpace.keyCode)
        XCTAssertEqual(pressCount, 1)
        XCTAssertNil(panel.handleVoiceInputKeyEvent(shortcutKeyUp, keyWindow: window))
        XCTAssertNil(panel.trackedVoiceInputKeyCode)
        XCTAssertEqual(releaseCount, 102)
        XCTAssertEqual(forcedStopCount, 3)
    }

    func testEditorInteractionUIBlocksShortcutUntilDismissed() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        var pressCount = 0
        panel.configure(panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onPress: {
                pressCount += 1
                return true
            }
        ))
        let window = mountedWindow(for: panel)
        defer { window.close() }
        let editor = try XCTUnwrap(panel.editorController.view)
        panel.editorController.bridgeController?.focusEditorAtDocumentEnd()
        XCTAssertTrue(editor.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))
        let event = try keyEvent(
            keyCode: PhysicalKeyboardShortcut.controlShiftSpace.keyCode,
            characters: " ",
            modifiers: [.control, .shift]
        )

        XCTAssertTrue(panel.handleVoiceInputKeyEvent(event, keyWindow: window) === event)
        XCTAssertEqual(pressCount, 0)

        panel.configure(panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: false,
            isVoiceInteractionLocked: true
        ))
        panel.configure(panelConfiguration(
            descriptor: .controlShiftSpace,
            isEnabled: true,
            onPress: {
                pressCount += 1
                return true
            }
        ))

        let currentEditor = try XCTUnwrap(panel.editorController.view)
        panel.editorController.bridgeController?.focusEditorAtDocumentEnd()
        window.makeKeyAndOrderFront(nil)
        XCTAssertFalse(currentEditor.hasPresentedEditorInteractionUI)
        XCTAssertTrue(panel.canHandleVoiceInputShortcut(keyWindow: window))
        XCTAssertNil(panel.trackedVoiceInputKeyCode)
        let shortcut = try XCTUnwrap(panel.configuration?.voiceInputShortcutConfiguration)
        XCTAssertTrue(shortcut.isEnabled)
        XCTAssertTrue(try XCTUnwrap(shortcut.descriptor).matches(event: event))
        XCTAssertNil(panel.handleVoiceInputKeyEvent(event, keyWindow: window))
        XCTAssertEqual(pressCount, 1)
    }

    func panelConfiguration(
        descriptor: PhysicalKeyboardShortcut? = nil,
        isEnabled: Bool = false,
        isVoiceInteractionLocked: Bool = false,
        voiceEditorHandle: AppKitChatComposerEditorHandle? = nil,
        onVoiceInputAvailabilityChange: @escaping () -> Void = {},
        interactionOverlayConfiguration: AppKitComposerOverlayConfiguration? = nil,
        onEscape: @escaping () -> Bool = { false },
        onPress: @escaping () -> Bool = { false },
        onRelease: @escaping (Bool) -> Bool = { _ in false },
        onForcedStop: @escaping () -> Void = {}
    ) -> AppKitChatComposerPanelConfiguration {
        AppKitChatComposerPanelConfiguration(
            bodyConfiguration: AppKitChatComposerBodyConfiguration(
                text: "Draft",
                mode: .idle,
                defaultEnterBehavior: .queue,
                isStopConfirmationArmed: false,
                supportsMidTurnSteering: true,
                isProjectTrustBlocked: false,
                isHandoffSteeringPromptActive: false,
                isHandoffOutputPromptActive: false,
                handoffSteeringCountdown: nil,
                sendCountdown: nil,
                hasQueuedMessages: false,
                hasTopContent: false,
                workingDirectory: nil,
                requestFirstResponder: nil,
                isVoiceInteractionLocked: isVoiceInteractionLocked,
                voiceEditorHandle: voiceEditorHandle,
                onVoiceInputAvailabilityChange: onVoiceInputAvailabilityChange,
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] },
                onSubmit: {},
                onSteer: {},
                onStop: {},
                onStopConfirmationChange: { _ in },
                onFocusRequestConsumed: { _ in }
            ),
            interactionOverlayConfiguration: interactionOverlayConfiguration,
            showsTopDivider: false,
            layout: .init(horizontalPadding: NSEdgeInsetsZero, topContentSpacing: 0, actionRowSpacing: 0),
            voiceInputShortcutConfiguration: shortcutConfiguration(
                descriptor: descriptor,
                isEnabled: isEnabled,
                onEscape: onEscape,
                onPress: onPress,
                onRelease: onRelease,
                onForcedStop: onForcedStop
            )
        )
    }

    private func shortcutConfiguration(
        descriptor: PhysicalKeyboardShortcut?,
        isEnabled: Bool,
        onEscape: @escaping () -> Bool = { false },
        onPress: @escaping () -> Bool = { false },
        onRelease: @escaping (Bool) -> Bool,
        onForcedStop: @escaping () -> Void
    ) -> AppKitVoiceInputShortcutConfiguration {
        AppKitVoiceInputShortcutConfiguration(
            descriptor: descriptor,
            isEnabled: isEnabled,
            onEscape: onEscape,
            onPress: onPress,
            onRelease: onRelease,
            onForcedStop: onForcedStop
        )
    }

    private func keyEvent(
        type: NSEvent.EventType = .keyDown,
        keyCode: UInt16,
        characters: String,
        modifiers: NSEvent.ModifierFlags = [],
        isARepeat: Bool = false
    ) throws -> NSEvent {
        try XCTUnwrap(NSEvent.keyEvent(
            with: type,
            location: .zero,
            modifierFlags: modifiers,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: characters,
            isARepeat: isARepeat,
            keyCode: keyCode
        ))
    }

    private func mountedWindow(for panel: AppKitChatComposerPanelView) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: -1400, y: -1100, width: 420, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = panel
        window.makeKeyAndOrderFront(nil)
        window.layoutIfNeeded()
        panel.layoutSubtreeIfNeeded()
        return window
    }

}
