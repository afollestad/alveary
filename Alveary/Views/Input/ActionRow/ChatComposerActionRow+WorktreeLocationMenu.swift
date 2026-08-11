@preconcurrency import AppKit

extension ChatComposerActionRowView {
    func toggleWorktreeLocationMenu() {
        guard let configuration,
              !configuration.areControlsDisabled,
              configuration.showWorktreePicker else {
            closeWorktreeLocationMenu()
            return
        }
        if let worktreePopover {
            if worktreePopover.isShown {
                closeWorktreeLocationMenu()
                return
            }
            finishWorktreeLocationMenuClose(for: worktreePopover)
        }

        let selectedOption = ChatComposerWorktreeLocationPresentation.selectedOption(
            usesWorktree: configuration.selectedUseWorktree
        )
        let controller = ComposerWorktreeMenuViewController(
            options: ChatComposerWorktreeLocationPresentation.options(),
            selectedValue: selectedOption.value,
            onUseWorktreeSelected: { [weak self] useWorktree in
                self?.configuration?.onUseWorktreeChange(useWorktree)
            },
            onRequestCloseMainMenu: { [weak self] in
                self?.closeWorktreeLocationMenu()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        worktreeMenuController = controller
        worktreePopover = popover
        popover.show(relativeTo: worktreeButton.bounds, of: worktreeButton, preferredEdge: .minY)
    }

    func closeWorktreeLocationMenu() {
        guard let popover = worktreePopover else {
            worktreeButton.releaseMenuFocusIfNeeded()
            return
        }
        popover.performClose(nil)
        finishWorktreeLocationMenuClose(for: popover)
    }

    func finishWorktreeLocationMenuClose(for popover: NSPopover) {
        guard worktreePopover === popover else {
            return
        }
        popover.delegate = nil
        worktreePopover = nil
        worktreeMenuController = nil
        worktreeButton.releaseMenuFocusIfNeeded()
    }
}
