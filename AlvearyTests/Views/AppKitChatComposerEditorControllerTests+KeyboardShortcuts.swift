import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitChatComposerEditorControllerTests {
    func testKeyboardShortcutsUseCommandReturnForAlternateBehavior() {
        let controller = AppKitChatComposerEditorController()
        let shortcuts = controller.blockInputKeyboardShortcuts()

        XCTAssertNotNil(shortcuts[commandReturnShortcut])
        XCTAssertNil(shortcuts[.optionReturn])
    }

    func testCommandReturnRoutesToAlternateSteerForQueueDefaultEvenWhenTextIsEmpty() {
        let controller = AppKitChatComposerEditorController()
        var submitCount = 0
        var steerCount = 0
        var alternateSteerCount = 0
        controller.configure(makeConfiguration(
            text: "",
            isTextEffectivelyEmpty: true,
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue,
            onSubmit: { submitCount += 1 },
            onSteer: { steerCount += 1 },
            onAlternateSteer: { alternateSteerCount += 1 }
        ))

        let result = controller.blockInputKeyboardShortcuts()[commandReturnShortcut]?(shortcutContext(commandReturnShortcut))

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(submitCount, 0)
        XCTAssertEqual(steerCount, 0)
        XCTAssertEqual(alternateSteerCount, 1)
    }

    func testPlainReturnRoutesToSteerCallbackForSteerDefault() {
        let controller = AppKitChatComposerEditorController()
        var submitCount = 0
        var steerCount = 0
        var alternateSteerCount = 0
        controller.configure(makeConfiguration(
            text: "Steer",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer,
            onSubmit: { submitCount += 1 },
            onSteer: { steerCount += 1 },
            onAlternateSteer: { alternateSteerCount += 1 }
        ))

        let result = controller.blockInputKeyboardShortcuts()[.returnKey]?(shortcutContext(.returnKey))

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(submitCount, 0)
        XCTAssertEqual(steerCount, 1)
        XCTAssertEqual(alternateSteerCount, 0)
    }

    func testCommandReturnRoutesToSubmitForSteerDefault() {
        let controller = AppKitChatComposerEditorController()
        var submitCount = 0
        var steerCount = 0
        var alternateSteerCount = 0
        controller.configure(makeConfiguration(
            text: "Queue",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .steer,
            onSubmit: { submitCount += 1 },
            onSteer: { steerCount += 1 },
            onAlternateSteer: { alternateSteerCount += 1 }
        ))

        let result = controller.blockInputKeyboardShortcuts()[commandReturnShortcut]?(shortcutContext(commandReturnShortcut))

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(submitCount, 1)
        XCTAssertEqual(steerCount, 0)
        XCTAssertEqual(alternateSteerCount, 0)
    }

    func testCommandReturnDoesNotRouteAlternateSteerWhenProjectTrustBlocked() {
        let controller = AppKitChatComposerEditorController()
        var submitCount = 0
        var steerCount = 0
        var alternateSteerCount = 0
        controller.configure(makeConfiguration(
            text: "Blocked",
            mode: .busy(canStop: true),
            defaultEnterBehavior: .queue,
            isProjectTrustBlocked: true,
            onSubmit: { submitCount += 1 },
            onSteer: { steerCount += 1 },
            onAlternateSteer: { alternateSteerCount += 1 }
        ))

        let result = controller.blockInputKeyboardShortcuts()[commandReturnShortcut]?(shortcutContext(commandReturnShortcut))

        XCTAssertEqual(result, .handled)
        XCTAssertEqual(submitCount, 0)
        XCTAssertEqual(steerCount, 0)
        XCTAssertEqual(alternateSteerCount, 0)
    }

    func testHostedBlockInputViewPerformsCommandReturnShortcut() throws {
        let panel = AppKitChatComposerPanelView(frame: NSRect(x: 0, y: 0, width: 420, height: 160))
        var alternateSteerCount = 0
        panel.configure(AppKitChatComposerPanelConfiguration(
            bodyConfiguration: makeConfiguration(
                text: "",
                isTextEffectivelyEmpty: true,
                mode: .busy(canStop: true),
                defaultEnterBehavior: .queue,
                onAlternateSteer: { alternateSteerCount += 1 }
            ),
            showsTopDivider: false,
            layout: AppKitChatComposerPanelView.Layout(
                horizontalPadding: NSEdgeInsets(top: 0, left: 20, bottom: 0, right: 20),
                topContentSpacing: 0,
                actionRowSpacing: 0
            )
        ))
        panel.layoutSubtreeIfNeeded()
        let editor = try XCTUnwrap(panel.editorControllerForTesting.view)

        XCTAssertTrue(editor.performKeyEquivalent(with: try commandReturnEvent()))
        XCTAssertEqual(alternateSteerCount, 1)
    }
}

private let commandReturnShortcut = BlockInputKeyboardShortcut(key: .return, modifiers: .command)

private func shortcutContext(_ shortcut: BlockInputKeyboardShortcut) -> BlockInputKeyboardShortcutContext {
    BlockInputKeyboardShortcutContext(
        shortcut: shortcut,
        selection: nil,
        activeBlock: nil,
        focusSource: .blockText,
        isRepeat: false
    )
}

private func commandReturnEvent() throws -> NSEvent {
    try XCTUnwrap(NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: .command,
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\r",
        charactersIgnoringModifiers: "\r",
        isARepeat: false,
        keyCode: 36
    ))
}
