@preconcurrency import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ComposerVoiceInputButtonTests: XCTestCase {
    func testMicPressUsesCircularPressedStateAndRestoresComposerFocusOnRelease() throws {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try XCTUnwrap(window.contentView)
        let editor = NSTextView(frame: NSRect(x: 20, y: 60, width: 200, height: 40))
        let button = ComposerVoiceInputButton(frame: NSRect(x: 240, y: 60, width: 30, height: 30))
        contentView.addSubview(editor)
        contentView.addSubview(button)
        button.configure(voiceInputConfiguration())
        XCTAssertTrue(window.makeFirstResponder(editor))

        button.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 255, y: 75)))

        XCTAssertTrue(window.firstResponder === button)
        #if DEBUG
        XCTAssertEqual(button.debugBackgroundAlpha, 0.18, accuracy: 0.001)
        #endif

        button.forceMouseRelease()

        XCTAssertTrue(window.firstResponder === editor)
        #if DEBUG
        XCTAssertEqual(button.debugBackgroundAlpha, 0, accuracy: 0.001)
        #endif
    }

    func testMicSymbolAndButtonFrameCenterOnSendAction() throws {
        let voiceInput = voiceInputConfiguration()
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 900, height: 30))
        row.configure(makeConfiguration(mode: .idle, voiceInput: voiceInput))
        row.layoutSubtreeIfNeeded()

        let micButton = row.voiceInputButton
        let sendButton = try XCTUnwrap(row.rowSubviews.compactMap { $0 as? ComposerActionButton }.first)
        XCTAssertEqual(micButton.frame.midY, sendButton.frame.midY, accuracy: 0.001)
        #if DEBUG
        let symbolRect = try XCTUnwrap(micButton.debugSymbolRect)
        XCTAssertEqual(symbolRect.midY, micButton.bounds.midY, accuracy: 0.001)
        #endif
    }

    func testRejectedMicPressRestoresFocusWithoutSendingRelease() throws {
        let fixture = try mountedMicButton()
        var releaseCount = 0
        fixture.button.configure(voiceInputConfiguration(
            onPress: { false },
            onRelease: { _ in
                releaseCount += 1
                return true
            }
        ))
        XCTAssertTrue(fixture.window.makeFirstResponder(fixture.editor))

        fixture.button.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 255, y: 75)))
        fixture.button.forceMouseRelease()

        XCTAssertTrue(
            fixture.window.firstResponder === fixture.editor,
            "First responder after release: \(String(describing: fixture.window.firstResponder))"
        )
        XCTAssertEqual(releaseCount, 0)
        #if DEBUG
        XCTAssertEqual(fixture.button.debugBackgroundAlpha, 0, accuracy: 0.001)
        #endif
    }

    func testMouseExitForcesReleaseAndRestoresComposerFocus() throws {
        let fixture = try mountedMicButton()
        var forcedReleases: [Bool] = []
        fixture.button.configure(voiceInputConfiguration(onRelease: { forced in
            forcedReleases.append(forced)
            return true
        }))
        XCTAssertTrue(fixture.window.makeFirstResponder(fixture.editor))

        fixture.button.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 255, y: 75)))
        fixture.button.mouseExited(with: try mouseEvent(type: .mouseMoved, location: NSPoint(x: 10, y: 10)))

        XCTAssertEqual(forcedReleases, [true])
        XCTAssertTrue(fixture.window.firstResponder === fixture.editor)
    }

    func testMicDeinitRemovesActiveLocalMouseMonitor() async throws {
        var removalCount = 0
        var button: ComposerVoiceInputButton? = ComposerVoiceInputButton()
        weak let weakButton = button
        button?.configure(voiceInputConfiguration())
        #if DEBUG
        button?.debugObserveMouseEventMonitorRemoval {
            removalCount += 1
        }
        #endif
        button?.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 15, y: 15)))

        button = nil
        for _ in 0..<20 where weakButton != nil {
            await Task.yield()
        }

        XCTAssertNil(weakButton)
        XCTAssertEqual(removalCount, 1)
    }

    func testSynchronousDisableDuringAcceptedMicPressStillRestoresFocusAndReleasesOnce() throws {
        let fixture = try mountedMicButton()
        var releaseCount = 0
        let onRelease: (Bool) -> Bool = { _ in
            releaseCount += 1
            return true
        }
        fixture.button.configure(voiceInputConfiguration(
            onPress: { [weak button = fixture.button] in
                button?.configure(self.voiceInputConfiguration(
                    phase: .starting,
                    isEnabled: false,
                    onRelease: onRelease
                ))
                return true
            },
            onRelease: onRelease
        ))
        XCTAssertTrue(fixture.window.makeFirstResponder(fixture.editor))

        fixture.button.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 255, y: 75)))

        #if DEBUG
        XCTAssertTrue(fixture.button.debugMouseFocusRestoreTarget === fixture.editor)
        #endif
        fixture.button.forceMouseRelease()
        fixture.button.forceMouseRelease()
        XCTAssertTrue(
            fixture.window.firstResponder === fixture.editor,
            "First responder after synchronous disable release: \(String(describing: fixture.window.firstResponder))"
        )
        XCTAssertEqual(releaseCount, 1)
    }

    func testCancelAccessibilityActionOnlyAppearsWhileDictationCanBeCancelled() {
        let button = ComposerVoiceInputButton()
        var cancellationCount = 0

        button.configure(voiceInputConfiguration(phase: .ready))
        XCTAssertEqual(button.accessibilityCustomActions()?.count, 0)

        button.configure(voiceInputConfiguration(phase: .recording))
        XCTAssertEqual(button.accessibilityCustomActions()?.map(\.name), ["Cancel Dictation"])

        button.configure(voiceInputConfiguration(
            phase: .finalizing,
            isEnabled: false,
            onAccessibilityCancel: {
                cancellationCount += 1
                return true
            }
        ))
        XCTAssertEqual(button.accessibilityCustomActions()?.map(\.name), ["Cancel Dictation"])
        XCTAssertTrue(button.isAccessibilityEnabled())
        XCTAssertFalse(button.accessibilityPerformPress())
        XCTAssertTrue(button.accessibilityCustomActions()?.first?.handler?() == true)
        XCTAssertEqual(cancellationCount, 1)

        button.configure(voiceInputConfiguration(phase: .cleanup))
        XCTAssertEqual(button.accessibilityCustomActions()?.count, 0)
    }

    func testFocusedMicIgnoresRepeatedAndModifiedActivationKeys() throws {
        let button = ComposerVoiceInputButton()
        var toggleCount = 0
        button.configure(voiceInputConfiguration(onAccessibilityToggle: {
            toggleCount += 1
        }))

        button.keyDown(with: try keyEvent(keyCode: 49, characters: " "))
        button.keyDown(with: try keyEvent(keyCode: 49, characters: " ", isARepeat: true))
        button.keyDown(with: try keyEvent(keyCode: 36, characters: "\r", modifiers: .command))

        XCTAssertEqual(toggleCount, 1)
    }

    func testMountedMicRefreshesLiveAccessibilityDisplayOptions() {
        let button = ComposerVoiceInputButton()
        button.configure(voiceInputConfiguration(phase: .preparing(message: "Downloading…", fraction: nil)))
        #if DEBUG
        XCTAssertTrue(button.debugShowsSpinner)
        XCTAssertFalse(button.debugSpinnerIsAccessibilityElement)
        XCTAssertFalse(button.debugIncreasesContrast)
        button.debugSetAccessibilityDisplayOptionsProvider {
            (reducesMotion: true, increasesContrast: true)
        }

        NSWorkspace.shared.notificationCenter.post(
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )

        XCTAssertFalse(button.debugShowsSpinner)
        XCTAssertTrue(button.debugIncreasesContrast)
        #endif
    }

    func testAttachedSheetBlocksMouseKeyboardAndAccessibilityMicActivation() throws {
        var pressCount = 0
        let voiceInput = voiceInputConfiguration(onPress: {
            pressCount += 1
            return true
        }, onAccessibilityToggle: {
            pressCount += 1
        })
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        panel.configure(panelConfiguration(voiceInput: voiceInput))
        let window = NSWindow(
            contentRect: NSRect(x: -1400, y: -1100, width: 420, height: 160),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = panel
        window.makeKeyAndOrderFront(nil)
        let sheet = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 100),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        sheet.isReleasedWhenClosed = false
        window.beginSheet(sheet)
        defer {
            if window.attachedSheet === sheet {
                window.endSheet(sheet)
            }
            sheet.orderOut(nil)
            window.close()
        }
        let button = panel.actionRow.voiceInputButton

        XCTAssertFalse(button.accessibilityPerformPress())
        button.mouseDown(with: try mouseEvent(type: .leftMouseDown, location: NSPoint(x: 15, y: 15)))
        XCTAssertTrue(window.makeFirstResponder(button))
        button.keyDown(with: try keyEvent(keyCode: 49, characters: " "))
        XCTAssertEqual(pressCount, 0)

    }

    func testHeldShortcutBlocksMouseAndAccessibilityMicUntilItsKeyUp() throws {
        let voiceInput = voiceInputConfiguration()
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        panel.configure(panelConfiguration(voiceInput: voiceInput))
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
        let button = panel.actionRow.voiceInputButton
        let shortcutKeyCode = PhysicalKeyboardShortcut.controlShiftSpace.keyCode

        panel.trackedVoiceInputKeyCode = shortcutKeyCode
        XCTAssertFalse(panel.canActivateVoiceInputControl(keyWindow: window))
        XCTAssertFalse(button.accessibilityPerformPress())

        panel.trackedVoiceInputKeyCode = nil
        panel.suppressedVoiceInputKeyUpCode = shortcutKeyCode
        XCTAssertFalse(panel.canActivateVoiceInputControl(keyWindow: window))
        XCTAssertFalse(button.accessibilityPerformPress())

        let keyUp = try keyEvent(type: .keyUp, keyCode: shortcutKeyCode, characters: " ")
        XCTAssertNil(panel.handleVoiceInputKeyEvent(keyUp, keyWindow: window))
        XCTAssertNil(panel.suppressedVoiceInputKeyUpCode)
        XCTAssertTrue(panel.canActivateVoiceInputControl(keyWindow: window))
    }

    private func voiceInputConfiguration(
        phase: ChatVoiceInputPhase = .ready,
        isEnabled: Bool = true,
        reducesMotion: Bool = false,
        increasesContrast: Bool = false,
        onPress: @escaping () -> Bool = { true },
        onRelease: @escaping (Bool) -> Bool = { _ in true },
        onAccessibilityToggle: @escaping () -> Void = {},
        onAccessibilityCancel: @escaping () -> Bool = { true }
    ) -> ComposerVoiceInputConfiguration {
        var configuration = ComposerVoiceInputConfiguration(
            phase: phase,
            isEnabled: isEnabled,
            shortcutDisplay: "⌃⇧Space",
            unavailableHelp: nil,
            onPress: onPress,
            onRelease: onRelease,
            onAccessibilityToggle: onAccessibilityToggle,
            onAccessibilityCancel: onAccessibilityCancel
        )
        configuration.reducesMotion = reducesMotion
        configuration.increasesContrast = increasesContrast
        return configuration
    }

    private func panelConfiguration(
        voiceInput: ComposerVoiceInputConfiguration
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
                loadFileCompletions: { [] },
                loadSkillCompletions: { [] },
                onSubmit: {},
                onSteer: {},
                onStop: {},
                onStopConfirmationChange: { _ in },
                onFocusRequestConsumed: { _ in }
            ),
            actionRowConfiguration: makeConfiguration(mode: .idle, voiceInput: voiceInput),
            showsTopDivider: false,
            layout: .init(horizontalPadding: NSEdgeInsetsZero, topContentSpacing: 0, actionRowSpacing: 0)
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

    private func mountedMicButton() throws -> MountedMicButton {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let contentView = try XCTUnwrap(window.contentView)
        let editor = NSTextView(frame: NSRect(x: 20, y: 60, width: 200, height: 40))
        let button = ComposerVoiceInputButton(frame: NSRect(x: 240, y: 60, width: 30, height: 30))
        contentView.addSubview(editor)
        contentView.addSubview(button)
        return MountedMicButton(window: window, editor: editor, button: button)
    }

    private func mouseEvent(type: NSEvent.EventType, location: NSPoint) throws -> NSEvent {
        try XCTUnwrap(NSEvent.mouseEvent(
            with: type,
            location: location,
            modifierFlags: [],
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        ))
    }
}

private struct MountedMicButton {
    let window: NSWindow
    let editor: NSTextView
    let button: ComposerVoiceInputButton
}
