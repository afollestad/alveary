@preconcurrency import AppKit

extension ChatComposerActionRowView {
    func togglePermissionMenu() {
        guard let configuration,
              !configuration.areControlsDisabled,
              !configuration.supportedPermissionModes.isEmpty else {
            closePermissionMenu()
            return
        }
        if let permissionPopover {
            if permissionPopover.isShown {
                closePermissionMenu()
                return
            }
            finishPermissionMenuClose(for: permissionPopover)
        }

        let controller = ComposerPermissionMenuViewController(
            options: configuration.supportedPermissionModes,
            selectedValue: configuration.selectedPermissionMode,
            onPermissionSelected: { [weak self] value in
                self?.configuration?.onPermissionModeChange(value)
            },
            onRequestCloseMainMenu: { [weak self] in
                self?.closePermissionMenu()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        permissionMenuController = controller
        permissionPopover = popover
        popover.show(relativeTo: permissionButton.bounds, of: permissionButton, preferredEdge: .minY)
    }

    func closePermissionMenu() {
        guard let popover = permissionPopover else {
            permissionButton.releaseMenuFocusIfNeeded()
            return
        }
        popover.performClose(nil)
        finishPermissionMenuClose(for: popover)
    }

    func finishPermissionMenuClose(for popover: NSPopover) {
        guard permissionPopover === popover else {
            return
        }
        popover.delegate = nil
        permissionPopover = nil
        permissionMenuController = nil
        permissionButton.releaseMenuFocusIfNeeded()
    }
}
