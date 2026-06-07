import AppKit
import XCTest

@testable import Alveary

@MainActor
final class ChatComposerPlusMenuTests: XCTestCase {
    func testPlusButtonMatchesMenuHeightAndPinsToLeadingEdge() throws {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        row.configure(makeConfiguration(mode: .idle))

        row.layoutSubtreeIfNeeded()

        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        XCTAssertEqual(plusButton.accessibilityLabel(), "Open composer actions")
        XCTAssertEqual(plusButton.intrinsicContentSize.width, 24)
        XCTAssertEqual(plusButton.intrinsicContentSize.height, 24)

        let plusFrame = plusButton.convert(plusButton.bounds, to: row)
        XCTAssertEqual(plusFrame.minX, 0, accuracy: 1)
        XCTAssertEqual(plusFrame.height, 24, accuracy: 1)
        XCTAssertEqual(plusFrame.midY, row.bounds.midY, accuracy: 1)
    }

    func testPlusMenuRowsRouteActionsAndPlanRowToggles() throws {
        var addFilesCount = 0
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: { addFilesCount += 1 },
            onPlanModeChange: { planModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let addFilesRow = try XCTUnwrap(
            controller.view.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Add photos and files" }
        )
        XCTAssertTrue(addFilesRow.accessibilityPerformPress())
        XCTAssertEqual(addFilesCount, 1)

        let planRow = try XCTUnwrap(
            controller.view.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle plan mode" }
        )
        XCTAssertTrue(planRow.accessibilityPerformPress())
        XCTAssertTrue(planRow.accessibilityPerformPress())
        XCTAssertEqual(planModeChanges, [true, false])
    }

    func testPlusMenuPlanRowIgnoresPressesWhenDisabled() throws {
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: false,
            planModeDisabledTooltip: "Unsupported",
            onAddPhotosAndFiles: {},
            onPlanModeChange: { planModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let planRow = try XCTUnwrap(
            controller.view.descendants(of: NSView.self).first { $0.accessibilityLabel() == "Toggle plan mode" }
        )
        XCTAssertFalse(planRow.accessibilityPerformPress())
        XCTAssertTrue(planModeChanges.isEmpty)
    }

    func testPlusMenuRowsActivateFromKeyboard() throws {
        var addFilesCount = 0
        var planModeChanges: [Bool] = []
        let controller = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: false,
            isPlanModeToggleEnabled: true,
            planModeDisabledTooltip: nil,
            onAddPhotosAndFiles: { addFilesCount += 1 },
            onPlanModeChange: { planModeChanges.append($0) }
        ))
        controller.loadViewIfNeeded()

        let addFilesRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Add photos and files"
            }
        )
        let planRow = try XCTUnwrap(
            controller.view.descendants(of: ComposerPlusMenuRowView.self).first {
                $0.accessibilityLabel() == "Toggle plan mode"
            }
        )

        addFilesRow.keyDown(with: keyEvent(keyCode: 36))
        planRow.keyDown(with: keyEvent(keyCode: 49))

        XCTAssertEqual(addFilesCount, 1)
        XCTAssertEqual(planModeChanges, [true])
    }

    func testPopoverDidCloseReleasesPlusButtonFocus() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(plusButton))

        let popover = NSPopover()
        row.plusPopover = popover

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertFalse(window.firstResponder === plusButton)
        XCTAssertNil(row.plusPopover)
    }

    func testPopoverDidCloseLeavesUnrelatedFirstResponderIntact() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let focusTarget = FocusTargetView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
        row.addSubview(focusTarget)
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(focusTarget))

        let popover = NSPopover()
        row.plusPopover = popover

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertTrue(window.firstResponder === focusTarget)
        XCTAssertNil(row.plusPopover)
    }

    func testStalePopoverDidCloseDoesNotClearCurrentPopover() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(plusButton))

        let currentPopover = NSPopover()
        row.plusPopover = currentPopover

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: NSPopover()))

        XCTAssertTrue(row.plusPopover === currentPopover)
        XCTAssertTrue(window.firstResponder === plusButton)
    }

    func testDisablingControlsReleasesPlusButtonFocusWithoutPopover() throws {
        let fixture = makeWindowBackedActionRow()
        let row = fixture.row
        let plusButton = try XCTUnwrap(row.descendants(of: ComposerPlusButton.self).first)
        let window = fixture.window
        XCTAssertNil(row.plusPopover)
        XCTAssertTrue(window.makeFirstResponder(plusButton))

        row.configure(makeConfiguration(mode: .idle, areControlsDisabled: true))

        XCTAssertFalse(window.firstResponder === plusButton)
        XCTAssertNil(row.plusPopover)
    }
}

private final class FocusTargetView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

private struct WindowBackedActionRow {
    let row: ChatComposerActionRowView
    let window: NSWindow
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

@MainActor
private func makeWindowBackedActionRow() -> WindowBackedActionRow {
    let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
    row.configure(makeConfiguration(mode: .idle))
    let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = row
    row.layoutSubtreeIfNeeded()
    return WindowBackedActionRow(row: row, window: window)
}

private func keyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: keyCode == 49 ? " " : "\r",
        charactersIgnoringModifiers: keyCode == 49 ? " " : "\r",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}
