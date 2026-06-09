@preconcurrency import AppKit

extension ChatComposerActionRowView {
    func toggleReasoningMenu() {
        guard let configuration,
              !configuration.areControlsDisabled else {
            closeReasoningMenu()
            return
        }
        if let reasoningPopover {
            if reasoningPopover.isShown {
                closeReasoningMenu()
                return
            }
            finishReasoningMenuClose(for: reasoningPopover)
        }

        let controller = ComposerReasoningMenuViewController(
            configuration: configuration.reasoning,
            onRequestCloseMainMenu: { [weak self] in
                self?.closeReasoningMenu()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        reasoningMenuController = controller
        reasoningPopover = popover
        popover.show(relativeTo: reasoningButton.bounds, of: reasoningButton, preferredEdge: .minY)
    }

    func closeReasoningMenu() {
        guard let popover = reasoningPopover else {
            reasoningButton.releaseMenuFocusIfNeeded()
            return
        }
        popover.performClose(nil)
        finishReasoningMenuClose(for: popover)
    }

    func finishReasoningMenuClose(for popover: NSPopover) {
        guard reasoningPopover === popover else {
            return
        }
        reasoningMenuController?.closeModelMenu()
        reasoningMenuController?.closeSpeedMenu()
        popover.delegate = nil
        reasoningPopover = nil
        reasoningMenuController = nil
        reasoningButton.releaseMenuFocusIfNeeded()
    }
}

extension ChatComposerActionRowView.Configuration {
    var isReconfiguringSession: Bool {
        guard case .progressOnly(.reconfiguringSession) = mode else {
            return false
        }
        return true
    }
}
