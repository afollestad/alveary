import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerActionRowTests {
    func testTaskWorkspaceGrantPresentationUsesCanonicalHomeRelativePath() {
        let path = NSHomeDirectory() + "/Development/../Development/alveary"

        XCTAssertEqual(
            ComposerTaskWorkspacePresentation.grantDisplayPath(path),
            "~/Development/alveary"
        )
        XCTAssertEqual(
            ComposerTaskWorkspacePresentation.grantRemovalAccessibilityLabel(path),
            "Remove Access to ~/Development/alveary"
        )
    }

    func testTaskWorkspaceControlReplacesProjectWorktreeControl() throws {
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: .init(
                primaryRoot: "/tmp/private-task",
                grantedRoots: ["/tmp/grant-a", "/tmp/grant-b"],
                ownershipStrategy: .privateOwned,
                canEdit: true,
                disabledTooltip: nil,
                onAddFolders: { _ in },
                onRemoveGrant: { _ in }
            )
        ))

        let workspaceButton = try XCTUnwrap(row.taskWorkspaceActionRowDescendants(of: ComposerWorktreeLocationButton.self).first)
        XCTAssertEqual(workspaceButton.accessibilityLabel(), "Task workspace")
        XCTAssertEqual(workspaceButton.accessibilityValue() as? String, "Private workspace, 2 additional folders")
    }

    func testDisabledTaskWorkspaceControlExplainsWhyAndDisambiguatesGrantRemoval() throws {
        let row = ChatComposerActionRowView()
        let reason = "Wait for the task to become fully idle before changing folder access."
        row.configure(makeConfiguration(
            mode: .busy(canStop: true),
            showWorktreePicker: false,
            areControlsDisabled: true,
            taskWorkspace: .init(
                primaryRoot: "/tmp/project-worktree",
                grantedRoots: ["/A/Sources", "/B/Sources"],
                ownershipStrategy: .projectWorktreeOwned,
                canEdit: false,
                disabledTooltip: reason,
                onAddFolders: { _ in },
                onRemoveGrant: { _ in }
            )
        ))

        let workspaceButton = try XCTUnwrap(row.taskWorkspaceActionRowDescendants(of: ComposerWorktreeLocationButton.self).first)
        XCTAssertEqual(workspaceButton.accessibilityValue() as? String, "Task worktree, 2 additional folders")
        XCTAssertEqual(workspaceButton.toolTip, reason)
        XCTAssertEqual(workspaceButton.accessibilityHelp(), reason)
        XCTAssertEqual(row.taskWorkspaceGrantRemovalTitle("/A/Sources"), "Remove Access to /A/Sources")
        XCTAssertNotEqual(
            row.taskWorkspaceGrantRemovalTitle("/A/Sources"),
            row.taskWorkspaceGrantRemovalTitle("/B/Sources")
        )
    }

    func testIdleTaskWorkspaceControlExplainsWorkspaceSpecificDisabledReason() throws {
        let row = ChatComposerActionRowView()
        let reason = "Folder access can only be changed while the task has one conversation."
        row.configure(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            areControlsDisabled: false,
            taskWorkspace: .init(
                primaryRoot: "/tmp/private-task",
                grantedRoots: [],
                ownershipStrategy: .privateOwned,
                canEdit: false,
                disabledTooltip: reason,
                onAddFolders: { _ in },
                onRemoveGrant: { _ in }
            )
        ))

        let workspaceButton = try XCTUnwrap(row.taskWorkspaceActionRowDescendants(of: ComposerWorktreeLocationButton.self).first)
        XCTAssertTrue(workspaceButton.controlIsEnabled)
        XCTAssertEqual(workspaceButton.toolTip, reason)
        XCTAssertEqual(workspaceButton.accessibilityHelp(), reason)
    }

    func testTaskWorkspaceClickSurvivesEquivalentReconfiguration() {
        let workspace = makeTaskWorkspaceConfiguration()
        let fixture = makeWorkspaceWindowBackedActionRow(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: workspace
        ))
        let button = fixture.row.worktreeButton

        button.mouseDown(with: workspaceMouseEvent(type: .leftMouseDown, button: button, window: fixture.window))
        fixture.row.configure(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: workspace
        ))

        XCTAssertTrue(fixture.window.firstResponder === button)
        var actionCount = 0
        button.actionHandler = { actionCount += 1 }
        button.mouseUp(with: workspaceMouseEvent(type: .leftMouseUp, button: button, window: fixture.window))
        XCTAssertEqual(actionCount, 1)
    }

    func testChangingTaskWorkspaceControlToWorktreeCancelsPendingClickAndClosesMenuState() {
        let workspace = makeTaskWorkspaceConfiguration()
        let fixture = makeWorkspaceWindowBackedActionRow(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: workspace
        ))
        let button = fixture.row.worktreeButton
        let popover = NSPopover()
        fixture.row.taskWorkspacePopover = popover
        fixture.row.taskWorkspaceMenuController = ComposerTaskWorkspaceMenuViewController(
            configuration: workspace,
            onAddFolders: {},
            onRemoveGrant: { _ in },
            onRequestClose: {}
        )

        button.mouseDown(with: workspaceMouseEvent(type: .leftMouseDown, button: button, window: fixture.window))
        fixture.row.configure(makeConfiguration(mode: .idle, showWorktreePicker: true))

        XCTAssertFalse(fixture.window.firstResponder === button)
        XCTAssertNil(fixture.row.taskWorkspacePopover)
        XCTAssertNil(fixture.row.taskWorkspaceMenuController)
        var actionCount = 0
        button.actionHandler = { actionCount += 1 }
        button.mouseUp(with: workspaceMouseEvent(type: .leftMouseUp, button: button, window: fixture.window))
        XCTAssertEqual(actionCount, 0)
    }

    func testChangingWorktreeControlToTaskWorkspaceCancelsPendingClickAndClosesMenuState() {
        let fixture = makeWorkspaceWindowBackedActionRow(makeConfiguration(
            mode: .idle,
            showWorktreePicker: true
        ))
        let button = fixture.row.worktreeButton
        let popover = NSPopover()
        fixture.row.worktreePopover = popover
        fixture.row.worktreeMenuController = ComposerWorktreeMenuViewController(
            options: ChatComposerWorktreeLocationPresentation.options(),
            selectedValue: ChatComposerWorktreeLocationPresentation.localValue,
            onUseWorktreeSelected: { _ in },
            onRequestCloseMainMenu: {}
        )

        button.mouseDown(with: workspaceMouseEvent(type: .leftMouseDown, button: button, window: fixture.window))
        fixture.row.configure(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: makeTaskWorkspaceConfiguration()
        ))

        XCTAssertFalse(fixture.window.firstResponder === button)
        XCTAssertNil(fixture.row.worktreePopover)
        XCTAssertNil(fixture.row.worktreeMenuController)
        var actionCount = 0
        button.actionHandler = { actionCount += 1 }
        button.mouseUp(with: workspaceMouseEvent(type: .leftMouseUp, button: button, window: fixture.window))
        XCTAssertEqual(actionCount, 0)
    }

    func testEquivalentTaskWorkspaceReconfigurationPreservesMenuState() {
        let workspace = makeTaskWorkspaceConfiguration()
        let row = ChatComposerActionRowView()
        row.configure(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: workspace
        ))
        let popover = NSPopover()
        let controller = ComposerTaskWorkspaceMenuViewController(
            configuration: workspace,
            onAddFolders: {},
            onRemoveGrant: { _ in },
            onRequestClose: {}
        )
        row.taskWorkspacePopover = popover
        row.taskWorkspaceMenuController = controller

        row.configure(makeConfiguration(
            mode: .idle,
            showWorktreePicker: false,
            taskWorkspace: makeTaskWorkspaceConfiguration(grantedRoots: ["/tmp/grant"])
        ))

        XCTAssertTrue(row.taskWorkspacePopover === popover)
        XCTAssertTrue(row.taskWorkspaceMenuController === controller)
    }

    func testFinishingTaskWorkspaceMenuReleasesButtonFocusAndController() {
        let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
        let workspace = ChatComposerActionRowView.TaskWorkspaceConfiguration(
            primaryRoot: "/tmp/private-task",
            grantedRoots: [],
            ownershipStrategy: .privateOwned,
            canEdit: true,
            disabledTooltip: nil,
            onAddFolders: { _ in },
            onRemoveGrant: { _ in }
        )
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

        row.finishTaskWorkspaceMenuClose(for: popover)

        XCTAssertFalse(window.firstResponder === row.worktreeButton)
        XCTAssertNil(row.taskWorkspacePopover)
        XCTAssertNil(row.taskWorkspaceMenuController)
    }
}

private struct WorkspaceWindowBackedActionRow {
    let row: ChatComposerActionRowView
    let window: NSWindow
}

@MainActor
private func makeWorkspaceWindowBackedActionRow(
    _ configuration: ChatComposerActionRowView.Configuration
) -> WorkspaceWindowBackedActionRow {
    let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
    row.configure(configuration)
    let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = row
    row.layoutSubtreeIfNeeded()
    return WorkspaceWindowBackedActionRow(row: row, window: window)
}

@MainActor
private func makeTaskWorkspaceConfiguration(
    grantedRoots: [String] = []
) -> ChatComposerActionRowView.TaskWorkspaceConfiguration {
    ChatComposerActionRowView.TaskWorkspaceConfiguration(
        primaryRoot: "/tmp/private-task",
        grantedRoots: grantedRoots,
        ownershipStrategy: .privateOwned,
        canEdit: true,
        disabledTooltip: nil,
        onAddFolders: { _ in },
        onRemoveGrant: { _ in }
    )
}

@MainActor
private func workspaceMouseEvent(
    type: NSEvent.EventType,
    button: NSView,
    window: NSWindow
) -> NSEvent {
    let location = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
    return NSEvent.mouseEvent(
        with: type,
        location: location,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: window.windowNumber,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
    ) ?? NSEvent()
}

private extension NSView {
    func taskWorkspaceActionRowDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.taskWorkspaceActionRowDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
