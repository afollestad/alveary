import AppKit

extension ChatComposerActionRowView {
    func togglePlusMenu() {
        guard let configuration,
              !configuration.areControlsDisabled else {
            return
        }
        if let plusPopover, plusPopover.isShown {
            plusPopover.performClose(nil)
            self.plusPopover = nil
            return
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = ComposerPlusMenuViewController(configuration: .init(
            isPlanModeEnabled: configuration.isPlanModeEnabled,
            isPlanModeToggleEnabled: configuration.isPlanModeToggleEnabled,
            planModeDisabledTooltip: configuration.planModeDisabledTooltip,
            onAddPhotosAndFiles: { [weak self] in
                self?.plusPopover?.performClose(nil)
                self?.plusPopover = nil
                self?.configuration?.onAddPhotosAndFiles()
            },
            onPlanModeChange: { [weak self] isEnabled in
                self?.configuration?.onPlanModeChange(isEnabled)
            }
        ))
        plusPopover = popover
        popover.show(relativeTo: plusButton.bounds, of: plusButton, preferredEdge: .minY)
    }
}
