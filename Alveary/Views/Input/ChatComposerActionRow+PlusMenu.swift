@preconcurrency import AppKit

extension ChatComposerActionRowView {
    func togglePlusMenu() {
        guard let configuration,
              !configuration.areControlsDisabled else {
            closePlusMenu()
            return
        }
        if let plusPopover {
            if plusPopover.isShown {
                closePlusMenu()
                return
            }
            finishPlusMenuClose(for: plusPopover)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: configuration.isPlanModeEnabled,
            isPlanModeToggleEnabled: configuration.isPlanModeToggleEnabled,
            planModeDisabledTooltip: configuration.planModeDisabledTooltip,
            onAddPhotosAndFiles: { [weak self] in
                guard let self else {
                    return
                }
                closePlusMenu()
                self.configuration?.onAddPhotosAndFiles()
            },
            onPlanModeChange: { [weak self] isEnabled in
                self?.configuration?.onPlanModeChange(isEnabled)
            }
        ))
        plusPopover = popover
        popover.show(relativeTo: plusButton.bounds, of: plusButton, preferredEdge: .minY)
    }

    func closePlusMenu() {
        guard let popover = plusPopover else {
            plusButton.releaseMenuFocusIfNeeded()
            return
        }
        popover.performClose(nil)
        finishPlusMenuClose(for: popover)
    }

    private func finishPlusMenuClose(for popover: NSPopover) {
        guard plusPopover === popover else {
            return
        }
        popover.delegate = nil
        plusPopover = nil
        plusButton.releaseMenuFocusIfNeeded()
    }
}

extension ChatComposerActionRowView: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        guard let popover = notification.object as? NSPopover else {
            return
        }
        finishPlusMenuClose(for: popover)
        finishReasoningMenuClose(for: popover)
        finishPermissionMenuClose(for: popover)
        finishWorktreeLocationMenuClose(for: popover)
    }
}
