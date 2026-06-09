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
            },
            onContentSizeChanged: { [weak self] size in
                self?.applyReasoningPopoverContentSize(size)
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        popover.contentSize = controller.preferredContentSize
        reasoningMenuController = controller
        reasoningPopover = popover
        let anchorRect = captureReasoningPopoverAnchorRect()
        reasoningPopoverAnchorRect = anchorRect
        popover.show(relativeTo: anchorRect, of: self, preferredEdge: .minY)
        controller.alignContentViewToPopoverHost()
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
        reasoningPopoverAnchorRect = nil
        reasoningMenuController = nil
        reasoningButton.releaseMenuFocusIfNeeded()
    }

    func captureReasoningPopoverAnchorRect() -> NSRect {
        reasoningButton.convert(reasoningButton.bounds, to: self)
    }

    func applyReasoningPopoverContentSize(_ size: NSSize) {
        guard let popover = reasoningPopover,
              let controller = reasoningMenuController,
              popover.contentViewController === controller else {
            return
        }
        controller.preferredContentSize = size
        popover.contentSize = size
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
