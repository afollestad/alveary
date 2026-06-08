import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testWorktreeLocationMenuRowsUseTitleOnlyIconsAndTrailingChecks() throws {
        let controller = ComposerWorktreeMenuViewController(
            options: ChatComposerWorktreeLocationPresentation.options(),
            selectedValue: ChatComposerWorktreeLocationPresentation.worktreeValue,
            onUseWorktreeSelected: { _ in },
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.view is AppKitComposerPopoverSurfaceView)

        let header = try XCTUnwrap(
            controller.view.worktreeDescendants(of: ComposerReasoningHeaderView.self).first {
                $0.stringValue == "Thread location"
            }
        )
        let localRow = try XCTUnwrap(
            controller.view.worktreeDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Work locally"
            }
        )
        let worktreeRow = try XCTUnwrap(
            controller.view.worktreeDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "New worktree"
            }
        )

        XCTAssertNil(localRow.accessibilityValue())
        XCTAssertEqual(worktreeRow.accessibilityValue() as? String, "Selected")
        XCTAssertEqual(worktreeRow.frame.height, ComposerWorktreeMenuMetrics.rowHeight)
        #if DEBUG
        XCTAssertEqual(localRow.debugIconName, "laptopcomputer")
        XCTAssertEqual(localRow.debugIconRotationRadians, 0, accuracy: 0.0001)
        XCTAssertNil(localRow.debugSubtitle)
        XCTAssertNil(localRow.debugTrailingIconName)
        XCTAssertTrue(["arrow.trianglehead.branch", "arrow.triangle.branch"].contains(worktreeRow.debugIconName ?? ""))
        XCTAssertEqual(worktreeRow.debugIconRotationRadians, CGFloat.pi / 2, accuracy: 0.0001)
        XCTAssertNil(worktreeRow.debugSubtitle)
        XCTAssertEqual(worktreeRow.debugTrailingIconName, "checkmark")
        let iconLeft = try XCTUnwrap(worktreeRow.debugLeadingIconLeft)
        XCTAssertEqual(worktreeRow.frame.minX + iconLeft, header.frame.minX, accuracy: 1)
        #endif
    }

    func testWorktreeLocationMenuSelectionRoutesBooleanValueAndRequestsClose() throws {
        var selectedUseWorktree: Bool?
        var closeCount = 0
        let controller = ComposerWorktreeMenuViewController(
            options: ChatComposerWorktreeLocationPresentation.options(),
            selectedValue: ChatComposerWorktreeLocationPresentation.localValue,
            onUseWorktreeSelected: { selectedUseWorktree = $0 },
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()

        let worktreeRow = try XCTUnwrap(
            controller.view.worktreeDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "New worktree"
            }
        )
        XCTAssertTrue(worktreeRow.accessibilityPerformPress())

        XCTAssertEqual(selectedUseWorktree, true)
        XCTAssertEqual(closeCount, 1)
    }

    func testWorktreeLocationMenuUsesCompactWidthAndStandardIconSpacing() {
        XCTAssertEqual(ComposerWorktreeMenuMetrics.width, 280)
        XCTAssertEqual(
            ComposerReasoningMenuMetrics.iconTitleLeading -
                ComposerReasoningMenuMetrics.iconLeading -
                ComposerReasoningMenuMetrics.iconSlotSize,
            ComposerReasoningMenuMetrics.iconTextSpacing
        )
    }

    func testWorktreeLocationMenuEscapeRequestsClose() throws {
        var closeCount = 0
        let controller = ComposerWorktreeMenuViewController(
            options: ChatComposerWorktreeLocationPresentation.options(),
            selectedValue: ChatComposerWorktreeLocationPresentation.localValue,
            onUseWorktreeSelected: { _ in },
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()

        controller.view.keyDown(with: keyEvent(keyCode: 53))

        XCTAssertEqual(closeCount, 1)
    }

    func testWorktreeLocationPopoverDidCloseReleasesButtonFocus() {
        let fixture = makeWorktreeWindowBackedActionRow()
        let row = fixture.row
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(row.worktreeButton))

        let popover = NSPopover()
        row.worktreePopover = popover
        row.worktreeMenuController = ComposerWorktreeMenuViewController(
            options: [],
            selectedValue: "",
            onUseWorktreeSelected: { _ in },
            onRequestCloseMainMenu: {}
        )

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertFalse(window.firstResponder === row.worktreeButton)
        XCTAssertNil(row.worktreePopover)
        XCTAssertNil(row.worktreeMenuController)
    }

    func testDisablingControlsReleasesWorktreeButtonFocusWithoutPopover() {
        let fixture = makeWorktreeWindowBackedActionRow()
        let row = fixture.row
        let window = fixture.window
        XCTAssertNil(row.worktreePopover)
        XCTAssertTrue(window.makeFirstResponder(row.worktreeButton))

        row.configure(makeConfiguration(mode: .idle, areControlsDisabled: true))

        XCTAssertFalse(window.firstResponder === row.worktreeButton)
        XCTAssertNil(row.worktreePopover)
    }

    func testHidingWorktreePickerClosesWorktreePopover() {
        let fixture = makeWorktreeWindowBackedActionRow()
        let row = fixture.row
        let popover = NSPopover()
        row.worktreePopover = popover
        row.worktreeMenuController = ComposerWorktreeMenuViewController(
            options: [],
            selectedValue: "",
            onUseWorktreeSelected: { _ in },
            onRequestCloseMainMenu: {}
        )

        row.configure(makeConfiguration(mode: .idle, showWorktreePicker: false))

        XCTAssertNil(row.worktreePopover)
        XCTAssertNil(row.worktreeMenuController)
    }
}

private struct WorktreeWindowBackedActionRow {
    let row: ChatComposerActionRowView
    let window: NSWindow
}

@MainActor
private func makeWorktreeWindowBackedActionRow() -> WorktreeWindowBackedActionRow {
    let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
    row.configure(makeConfiguration(mode: .idle))
    let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = row
    row.layoutSubtreeIfNeeded()
    return WorktreeWindowBackedActionRow(row: row, window: window)
}

private extension NSView {
    func worktreeDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.worktreeDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func keyEvent(keyCode: UInt16) -> NSEvent {
    NSEvent.keyEvent(
        with: .keyDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        characters: "\u{1b}",
        charactersIgnoringModifiers: "\u{1b}",
        isARepeat: false,
        keyCode: keyCode
    ) ?? NSEvent()
}
