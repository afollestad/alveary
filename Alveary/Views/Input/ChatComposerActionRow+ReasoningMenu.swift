@preconcurrency import AppKit

extension ChatComposerActionRowView {
    static let reasoningPopoverPreferredEdge: NSRectEdge = .maxY

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
            onDisplaySelectionChanged: { [weak self] selection in
                self?.applyReasoningDisplaySelectionOverride(selection)
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
        popover.show(
            relativeTo: anchorRect,
            of: self,
            preferredEdge: Self.reasoningPopoverPreferredEdge
        )
        controller.alignContentViewToPopoverHost()
    }

    func closeReasoningMenu() {
        guard let popover = reasoningPopover else {
            applyReasoningDisplaySelectionOverride(nil)
            reasoningButton.releaseMenuFocusIfNeeded()
            return
        }
        popover.animates = false
        popover.performClose(nil)
        finishReasoningMenuClose(for: popover)
    }

    func finishReasoningMenuClose(for popover: NSPopover) {
        guard reasoningPopover === popover else {
            return
        }
        popover.animates = false
        reasoningMenuController?.cancelEffortPreview()
        popover.delegate = nil
        reasoningPopover = nil
        reasoningPopoverAnchorRect = nil
        reasoningMenuController = nil
        reasoningDisplaySelectionOverride = nil
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
        popover.animates = false
        popover.contentSize = size
        if popover.isShown, let anchorRect = reasoningPopoverAnchorRect {
            // Resizing a shown popover can make AppKit reconsider its edge. Reapply
            // the captured anchor and original preference so collapse stays above
            // the composer instead of flipping to the opposite side.
            popover.show(
                relativeTo: anchorRect,
                of: self,
                preferredEdge: Self.reasoningPopoverPreferredEdge
            )
        }
        controller.alignContentViewToPopoverHost()
    }

    func applyReasoningDisplaySelectionOverride(_ selection: ReasoningSelection?) {
        reasoningDisplaySelectionOverride = selection
        guard let configuration else { return }
        reasoningButton.configure(
            selection: selection ?? configuration.reasoning.selection,
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            showsProgress: configuration.isReconfiguringSession,
            actionHandler: { [weak self] in
                self?.toggleReasoningMenu()
            }
        )
        needsLayout = true
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
