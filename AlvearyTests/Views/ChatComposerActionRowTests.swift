import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerActionRowTests: XCTestCase {
    func testIdlePrimaryActionRoutesSubmitAndHonorsDisabledState() throws {
        let row = ChatComposerActionRowView()
        var submitCount = 0
        row.configure(
            makeConfiguration(
                mode: .idle,
                isPrimaryActionDisabled: false,
                onSubmit: { submitCount += 1 }
            )
        )

        let enabledButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertEqual(enabledButton.accessibilityLabel(), "Send")
        XCTAssertTrue(enabledButton.accessibilityPerformPress())
        XCTAssertEqual(submitCount, 1)

        row.configure(
            makeConfiguration(
                mode: .idle,
                isPrimaryActionDisabled: true,
                onSubmit: { submitCount += 1 }
            )
        )

        let disabledButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertFalse(disabledButton.accessibilityPerformPress())
        XCTAssertEqual(submitCount, 1)
    }

    func testStopActionRoutesStopAndUsesConfirmationAccessibilityCopy() throws {
        let row = ChatComposerActionRowView()
        var stopCount = 0
        row.configure(
            makeConfiguration(
                mode: .busy(canStop: true),
                isStopConfirmationArmed: true,
                onStop: { stopCount += 1 }
            )
        )

        let stopButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertEqual(stopButton.accessibilityLabel(), "Confirm stop")
        XCTAssertTrue(stopButton.accessibilityPerformPress())
        XCTAssertEqual(stopCount, 1)
    }

    func testBusyWithoutStopKeepsAccessibleDisabledSendingFootprint() throws {
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(mode: .busy(canStop: false)))

        let sendingSlot = try XCTUnwrap(
            row.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Sending message" }
        )
        XCTAssertEqual(sendingSlot.accessibilityRole(), .group)
        let footprintButton = try XCTUnwrap(row.descendants(of: ComposerActionButton.self).first)
        XCTAssertFalse(footprintButton.accessibilityPerformPress())
    }

    func testProgressOnlyWithoutStopShowsProgressLabelWithoutActionButtons() throws {
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(mode: .progressOnly(.sessionHandoff)))

        XCTAssertNotNil(row.descendants(of: NSTextField.self).first { $0.stringValue == "Handing off session..." })
        XCTAssertTrue(row.descendants(of: ComposerActionButton.self).isEmpty)
    }

    func testActionButtonDoesNotFireWhenDisabledBeforeMouseUp() {
        let button = ComposerActionButton(style: .primary)
        button.frame = NSRect(x: 0, y: 0, width: 76, height: 30)
        var submitCount = 0
        button.actionHandler = { submitCount += 1 }
        button.configure(
            title: "Send",
            symbolName: "paperplane.fill",
            isEnabled: true,
            accessibilityLabel: "Send"
        )

        button.mouseDown(with: mouseEvent(at: NSPoint(x: 10, y: 10)))
        button.configure(
            title: "Send",
            symbolName: "paperplane.fill",
            isEnabled: false,
            accessibilityLabel: "Send"
        )
        button.mouseUp(with: mouseEvent(at: NSPoint(x: 10, y: 10)))

        XCTAssertEqual(submitCount, 0)
    }

    func testDestructiveActionButtonFiresOnMouseDownOnce() {
        let button = ComposerActionButton(style: .destructive)
        button.frame = NSRect(x: 0, y: 0, width: 76, height: 30)
        var stopCount = 0
        button.actionHandler = { stopCount += 1 }
        button.configure(
            title: "Stop",
            symbolName: "stop.fill",
            isEnabled: true,
            accessibilityLabel: "Stop"
        )

        button.mouseDown(with: mouseEvent(type: .leftMouseDown, at: NSPoint(x: 10, y: 10)))
        XCTAssertEqual(stopCount, 1)

        button.mouseUp(with: mouseEvent(type: .leftMouseUp, at: NSPoint(x: 10, y: 10)))
        XCTAssertEqual(stopCount, 1)
    }

    func testDestructiveActionButtonStillFiresIfDisabledBeforeMouseUp() {
        let button = ComposerActionButton(style: .destructive)
        button.frame = NSRect(x: 0, y: 0, width: 76, height: 30)
        var stopCount = 0
        button.actionHandler = { stopCount += 1 }
        button.configure(
            title: "Stop",
            symbolName: "stop.fill",
            isEnabled: true,
            accessibilityLabel: "Stop"
        )

        button.mouseDown(with: mouseEvent(type: .leftMouseDown, at: NSPoint(x: 10, y: 10)))
        button.configure(
            title: "Stop",
            symbolName: "stop.fill",
            isEnabled: false,
            accessibilityLabel: "Stop"
        )
        button.mouseUp(with: mouseEvent(type: .leftMouseUp, at: NSPoint(x: 10, y: 10)))

        XCTAssertEqual(stopCount, 1)
    }

    func testMenuButtonUsesSwiftUIPickerHeightAndWidestOptionWidth() {
        let button = ComposerMenuButton()
        button.configure(
            title: "Default",
            options: [
                .init(value: "default", title: "Default"),
                .init(value: "acceptEdits", title: "Accept edits")
            ],
            selectedValue: "default",
            isEnabled: true,
            onSelect: { _ in }
        )

        let size = button.intrinsicContentSize
        XCTAssertEqual(size.height, 24)
        XCTAssertGreaterThan(size.width, 110)
    }
}

private func makeConfiguration(
    mode: ComposerMode,
    isPrimaryActionDisabled: Bool = false,
    isStopConfirmationArmed: Bool = false,
    onSubmit: @escaping () -> Void = {},
    onStop: @escaping () -> Void = {}
) -> ChatComposerActionRowView.Configuration {
    ChatComposerActionRowView.Configuration(
        modelOptions: [.init(value: "sonnet", title: "Sonnet")],
        selectedModel: "sonnet",
        supportedEffortLevels: [.init(value: "medium", title: "Medium")],
        selectedEffort: "medium",
        supportedPermissionModes: [.init(value: "default", title: "Default")],
        selectedPermissionMode: "default",
        showWorktreePicker: true,
        selectedUseWorktree: false,
        sessionLocationLabel: nil,
        usageSummary: nil,
        isTextEditorDisabled: false,
        areControlsDisabled: false,
        mode: mode,
        primaryActionTitle: "Send",
        primaryActionSystemImage: "paperplane.fill",
        isPrimaryActionDisabled: isPrimaryActionDisabled,
        isStopConfirmationArmed: isStopConfirmationArmed,
        composerActionRowHeight: 30,
        contextIndicatorKeyboardSpacing: 6,
        onModelChange: { _ in },
        onEffortChange: { _ in },
        onPermissionModeChange: { _ in },
        onUseWorktreeChange: { _ in },
        onSubmit: onSubmit,
        onStop: onStop,
        onShowKeymap: {}
    )
}

private extension NSView {
    func descendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.descendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func mouseEvent(type: NSEvent.EventType = .leftMouseUp, at point: NSPoint) -> NSEvent {
    NSEvent.mouseEvent(
        with: type,
        location: point,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    ) ?? NSEvent()
}
