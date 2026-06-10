import AppKit
import XCTest

@testable import Alveary

@MainActor
extension ChatComposerPlusMenuTests {
    func testPermissionMenuRowsUseDescriptionsLeadingIconsAndTrailingChecks() throws {
        let controller = ComposerPermissionMenuViewController(
            options: [
                .init(
                    value: "untrusted",
                    title: "Ask for approval",
                    description: "Always ask to edit external files and use the internet.",
                    symbolName: "hand.raised"
                ),
                .init(
                    value: "never",
                    title: "Full access",
                    description: "Unrestricted access to the internet and any file on your computer.",
                    symbolName: "exclamationmark.shield",
                    isWarning: true
                )
            ],
            selectedValue: "never",
            onPermissionSelected: { _ in },
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        XCTAssertTrue(controller.view is AppKitComposerPopoverSurfaceView)
        XCTAssertNil(controller.view.permissionDescendants(of: AppKitComposerPopoverDividerView.self).first)

        let header = try XCTUnwrap(
            controller.view.permissionDescendants(of: ComposerReasoningHeaderView.self).first {
                $0.stringValue == "Permission mode"
            }
        )

        let fullAccessRow = try XCTUnwrap(
            controller.view.permissionDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Full access"
            }
        )
        XCTAssertEqual(fullAccessRow.accessibilityValue() as? String, "Selected")
        XCTAssertEqual(fullAccessRow.frame.height, ComposerPermissionMenuMetrics.rowHeight)
        #if DEBUG
        XCTAssertEqual(fullAccessRow.debugIconName, "exclamationmark.shield")
        XCTAssertEqual(fullAccessRow.debugTrailingIconName, "checkmark")
        XCTAssertEqual(fullAccessRow.debugSubtitle, "Unrestricted access to the internet and any file on your computer.")
        XCTAssertTrue(fullAccessRow.debugIsWarning)
        let iconLeft = try XCTUnwrap(fullAccessRow.debugLeadingIconLeft)
        let titleLeading = try XCTUnwrap(fullAccessRow.debugTitleLeading)
        XCTAssertEqual(fullAccessRow.frame.minX + iconLeft, header.frame.minX, accuracy: 1)
        XCTAssertEqual(
            titleLeading - ComposerReasoningMenuMetrics.iconLeading - ComposerReasoningMenuMetrics.iconSlotSize,
            ComposerReasoningMenuMetrics.iconTextSpacing,
            accuracy: 1
        )
        #endif
    }

    func testPermissionPresentationUsesDisplayNamesForClaudeRowsAndButton() {
        let options = ChatComposerPermissionPresentation.options(
            providerID: "claude",
            permissionModes: [
                PermissionModeOption(
                    value: "default",
                    label: "Default",
                    description: "Ask before file edits and restricted tool actions."
                ),
                PermissionModeOption(
                    value: "acceptEdits",
                    label: "Accept edits",
                    description: "Automatically allow file edits, but ask for other sensitive actions."
                ),
                PermissionModeOption(
                    value: "auto",
                    label: "Automatic",
                    description: "Automatically approve most actions with safety checks."
                ),
                PermissionModeOption(
                    value: "bypassPermissions",
                    label: "Bypass permissions",
                    description: ""
                )
            ]
        )

        XCTAssertEqual(options.map(\.title), ["Default", "Accept edits", "Automatic", "Bypass permissions"])
        XCTAssertEqual(options[3].description, "Bypass all permission checks. Use only in sandboxed environments.")
        XCTAssertEqual(options[3].symbolName, "exclamationmark.shield")
        XCTAssertTrue(options[3].isWarning)

        let button = ComposerPermissionButton()
        button.configure(
            option: options[0],
            height: ChatComposerActionRowView.defaultSettingsControlHeight,
            isEnabled: true,
            actionHandler: {}
        )
        XCTAssertEqual(button.accessibilityValue() as? String, "Default")
        #if DEBUG
        XCTAssertEqual(button.debugTitle, "Default")
        #endif
    }

    func testClaudeBypassPermissionsUsesWarningTreatmentInPermissionMenu() throws {
        let options = ChatComposerPermissionPresentation.options(
            providerID: "claude",
            permissionModes: [
                PermissionModeOption(value: "bypassPermissions", label: "Bypass permissions", description: "")
            ]
        )
        let controller = ComposerPermissionMenuViewController(
            options: options,
            selectedValue: "bypassPermissions",
            onPermissionSelected: { _ in },
            onRequestCloseMainMenu: {}
        )
        controller.loadViewIfNeeded()
        controller.view.layoutSubtreeIfNeeded()

        let bypassRow = try XCTUnwrap(
            controller.view.permissionDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Bypass permissions"
            }
        )
        XCTAssertEqual(bypassRow.accessibilityValue() as? String, "Selected")
        #if DEBUG
        XCTAssertEqual(bypassRow.debugIconName, "exclamationmark.shield")
        XCTAssertEqual(bypassRow.debugTrailingIconName, "checkmark")
        XCTAssertEqual(
            bypassRow.debugSubtitle,
            "Bypass all permission checks. Use only in sandboxed environments."
        )
        XCTAssertTrue(bypassRow.debugIsWarning)
        #endif
    }

    func testPermissionMenuSelectionRoutesOriginalValueAndRequestsClose() throws {
        var selectedValue: String?
        var closeCount = 0
        let controller = ComposerPermissionMenuViewController(
            options: [
                .init(
                    value: "untrusted",
                    title: "Ask for approval",
                    description: "Always ask to edit external files and use the internet.",
                    symbolName: "hand.raised"
                ),
                .init(
                    value: "on-request",
                    title: "Approve for me",
                    description: "Only ask for actions detected as potentially unsafe.",
                    symbolName: "lock.shield"
                )
            ],
            selectedValue: "untrusted",
            onPermissionSelected: { selectedValue = $0 },
            onRequestCloseMainMenu: { closeCount += 1 }
        )
        controller.loadViewIfNeeded()

        let approveRow = try XCTUnwrap(
            controller.view.permissionDescendants(of: ComposerReasoningMenuRowView.self).first {
                $0.accessibilityLabel() == "Approve for me"
            }
        )
        XCTAssertTrue(approveRow.accessibilityPerformPress())

        XCTAssertEqual(selectedValue, "on-request")
        XCTAssertEqual(closeCount, 1)
    }

    func testPermissionPopoverDidCloseReleasesPermissionButtonFocus() {
        let fixture = makePermissionWindowBackedActionRow()
        let row = fixture.row
        let window = fixture.window
        XCTAssertTrue(window.makeFirstResponder(row.permissionButton))

        let popover = NSPopover()
        row.permissionPopover = popover
        row.permissionMenuController = ComposerPermissionMenuViewController(
            options: [],
            selectedValue: "",
            onPermissionSelected: { _ in },
            onRequestCloseMainMenu: {}
        )

        row.popoverDidClose(Notification(name: NSPopover.didCloseNotification, object: popover))

        XCTAssertFalse(window.firstResponder === row.permissionButton)
        XCTAssertNil(row.permissionPopover)
        XCTAssertNil(row.permissionMenuController)
    }

    func testDisablingControlsReleasesPermissionButtonFocusWithoutPopover() {
        let fixture = makePermissionWindowBackedActionRow()
        let row = fixture.row
        let window = fixture.window
        XCTAssertNil(row.permissionPopover)
        XCTAssertTrue(window.makeFirstResponder(row.permissionButton))

        row.configure(makeConfiguration(mode: .idle, areControlsDisabled: true))

        XCTAssertFalse(window.firstResponder === row.permissionButton)
        XCTAssertNil(row.permissionPopover)
    }

    func testRemovingPermissionOptionsClosesPermissionPopover() {
        let fixture = makePermissionWindowBackedActionRow()
        let row = fixture.row
        let popover = NSPopover()
        row.permissionPopover = popover
        row.permissionMenuController = ComposerPermissionMenuViewController(
            options: [],
            selectedValue: "",
            onPermissionSelected: { _ in },
            onRequestCloseMainMenu: {}
        )

        row.configure(makeConfiguration(mode: .idle, supportedPermissionModes: []))

        XCTAssertNil(row.permissionPopover)
        XCTAssertNil(row.permissionMenuController)
    }
}

private struct PermissionWindowBackedActionRow {
    let row: ChatComposerActionRowView
    let window: NSWindow
}

@MainActor
private func makePermissionWindowBackedActionRow() -> PermissionWindowBackedActionRow {
    let row = ChatComposerActionRowView(frame: NSRect(x: 0, y: 0, width: 480, height: 30))
    row.configure(makeConfiguration(mode: .idle))
    let window = NSWindow(contentRect: row.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = row
    row.layoutSubtreeIfNeeded()
    return PermissionWindowBackedActionRow(row: row, window: window)
}

private extension NSView {
    func permissionDescendants<ViewType: NSView>(of type: ViewType.Type) -> [ViewType] {
        subviews.flatMap { child -> [ViewType] in
            var matches = child.permissionDescendants(of: type)
            if let typed = child as? ViewType {
                matches.insert(typed, at: 0)
            }
            return matches
        }
    }
}
