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
