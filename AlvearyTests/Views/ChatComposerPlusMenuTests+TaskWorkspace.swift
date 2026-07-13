import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testTaskWorkspaceMenuUsesSharedComposerPopoverChrome() throws {
        let homeGrant = NSHomeDirectory() + "/Development/grant-a"
        let controller = ComposerTaskWorkspaceMenuViewController(
            configuration: makeTaskWorkspaceConfiguration(grantedRoots: [homeGrant]),
            onAddFolders: {},
            onRemoveGrant: { _ in },
            onRequestClose: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.view is AppKitComposerPopoverSurfaceView)
        XCTAssertEqual(
            controller.view.taskWorkspaceDescendants(of: AppKitComposerPopoverDividerView.self).filter { !$0.isHidden }.count,
            2
        )
        XCTAssertNotNil(
            controller.view.taskWorkspaceDescendants(of: ComposerReasoningHeaderView.self).first {
                $0.stringValue == "Workspace"
            }
        )

        let primaryRow = try XCTUnwrap(
            controller.view.taskWorkspaceDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Private workspace: private-task"
            }
        )
        let addRow = try XCTUnwrap(
            controller.view.taskWorkspaceDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Add folder access"
            }
        )
        let removeRow = try XCTUnwrap(
            controller.view.taskWorkspaceDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Remove Access to ~/Development/grant-a"
            }
        )

        XCTAssertFalse(primaryRow.accessibilityPerformPress())
        XCTAssertEqual(primaryRow.toolTip, "/tmp/private-task")
        #if DEBUG
        XCTAssertEqual(primaryRow.debugIconName, "folder")
        XCTAssertEqual(primaryRow.debugSubtitle, "private-task")
        XCTAssertEqual(addRow.debugIconName, "folder.badge.plus")
        XCTAssertNil(addRow.debugSubtitle)
        XCTAssertEqual(removeRow.debugIconName, "folder.badge.minus")
        XCTAssertEqual(removeRow.debugSubtitle, "Click to remove")
        #endif
    }

    func testTaskWorkspaceMenuActionsRouteAndDisabledStateIsPreserved() throws {
        var addCount = 0
        var removedPath: String?
        let controller = ComposerTaskWorkspaceMenuViewController(
            configuration: makeTaskWorkspaceConfiguration(),
            onAddFolders: { addCount += 1 },
            onRemoveGrant: { removedPath = $0 },
            onRequestClose: {}
        )
        controller.loadViewIfNeeded()

        let addRow = try XCTUnwrap(
            controller.view.taskWorkspaceDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Add folder access"
            }
        )
        let removeRow = try XCTUnwrap(
            controller.view.taskWorkspaceDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Remove Access to /tmp/grant-a"
            }
        )
        XCTAssertTrue(addRow.accessibilityPerformPress())
        XCTAssertTrue(removeRow.accessibilityPerformPress())
        XCTAssertEqual(addCount, 1)
        XCTAssertEqual(removedPath, "/tmp/grant-a")

        let reason = "Wait until this task is idle."
        controller.update(configuration: makeTaskWorkspaceConfiguration(canEdit: false, disabledTooltip: reason))
        let disabledRows = controller.view.taskWorkspaceDescendants(of: ComposerReasoningMenuRowView.self)
        let disabledAddRow = try XCTUnwrap(disabledRows.first { $0.accessibilityLabel() == "Add folder access" })
        let disabledRemoveRow = try XCTUnwrap(
            disabledRows.first { $0.accessibilityLabel() == "Remove Access to /tmp/grant-a" }
        )
        XCTAssertFalse(disabledAddRow.accessibilityPerformPress())
        XCTAssertFalse(disabledRemoveRow.accessibilityPerformPress())
        XCTAssertEqual(disabledAddRow.toolTip, reason)
        XCTAssertEqual(disabledRemoveRow.toolTip, reason)
    }

    func testTaskWorkspaceMenuEscapeRequestsClose() {
        var closeCount = 0
        let controller = ComposerTaskWorkspaceMenuViewController(
            configuration: makeTaskWorkspaceConfiguration(),
            onAddFolders: {},
            onRemoveGrant: { _ in },
            onRequestClose: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()

        controller.view.keyDown(with: taskWorkspaceKeyEvent(keyCode: 53))

        XCTAssertEqual(closeCount, 1)
    }

    func testTaskWorkspaceMenuCapsLongGrantListsToScrollableHeight() throws {
        let grants = (0..<20).map { "/tmp/grant-\($0)" }
        let grantCount = grants.count
        XCTAssertGreaterThan(
            ComposerTaskWorkspaceMenuMetrics.documentHeight(grantCount: grantCount),
            ComposerTaskWorkspaceMenuMetrics.maxHeight
        )
        XCTAssertEqual(
            ComposerTaskWorkspaceMenuMetrics.contentSize(grantCount: grantCount).height,
            ComposerTaskWorkspaceMenuMetrics.maxHeight
        )

        let controller = ComposerTaskWorkspaceMenuViewController(
            configuration: makeTaskWorkspaceConfiguration(grantedRoots: grants),
            onAddFolders: {},
            onRemoveGrant: { _ in },
            onRequestClose: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        let scrollView = try XCTUnwrap(
            controller.view.taskWorkspaceDescendants(of: NSScrollView.self).first
        )
        XCTAssertTrue(scrollView.hasVerticalScroller)
        XCTAssertGreaterThan(scrollView.documentView?.frame.height ?? 0, controller.preferredContentSize.height)
    }

    func testTaskWorkspacePopoverDidCloseReleasesButtonFocus() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        let workspace = makeTaskWorkspaceConfiguration()
        row.configure(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: workspace
        ))
        let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
        window.contentView = row
        let popover = NSPopover()
        row.taskWorkspacePopover = popover
        row.taskWorkspaceMenuController = ComposerTaskWorkspaceMenuViewController(
            configuration: workspace,
            onAddFolders: {},
            onRemoveGrant: { _ in },
            onRequestClose: {}
        )
        XCTAssertTrue(window.makeFirstResponder(row.worktreeButton))

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertFalse(window.firstResponder === row.worktreeButton)
        XCTAssertNil(row.taskWorkspacePopover)
        XCTAssertNil(row.taskWorkspaceMenuController)
    }
}

@MainActor
private func makeTaskWorkspaceConfiguration(
    canEdit: Bool = true,
    disabledTooltip: String? = nil,
    grantedRoots: [String] = ["/tmp/grant-a"]
) -> ChatComposerActionRowView.TaskWorkspaceConfiguration {
    .init(
        primaryRoot: "/tmp/private-task",
        grantedRoots: grantedRoots,
        ownershipStrategy: .privateOwned,
        canEdit: canEdit,
        disabledTooltip: disabledTooltip,
        onAddFolders: { _ in },
        onRemoveGrant: { _ in }
    )
}

private extension NSView {
    func taskWorkspaceDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.taskWorkspaceDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}

private func taskWorkspaceKeyEvent(keyCode: UInt16) -> NSEvent {
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
