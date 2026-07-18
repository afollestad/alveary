@preconcurrency import AppKit

extension ChatComposerActionRowView {
    static let reasoningPopoverPreferredEdge: NSRectEdge = .maxY

    struct ReasoningModelSelectionRequest: Equatable {
        let providerID: String
        let modelID: String
    }

    enum ReasoningModelSelectionOutcome {
        case rejected
        case unchanged(ReasoningSelection)
        case applied(selection: ReasoningSelection)
    }

    struct ReasoningConfiguration {
        var selection: ReasoningSelection
        var modelGroups: [ReasoningModelGroup]
        var onEffortChange: (String) -> Bool
        var onSpeedChange: (AgentSpeedMode) -> Bool
        var onModelChange: (ReasoningModelSelectionRequest) -> ReasoningModelSelectionOutcome
    }

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
        }

        presentReasoningMenuIfNeeded()
    }

    func presentReasoningMenuIfNeeded() {
        guard let configuration,
              !configuration.areControlsDisabled else {
            closeReasoningMenu()
            return
        }
        if reasoningMenuIsPresentedOverride?() == true {
            return
        }
        if let reasoningPopover {
            guard !reasoningPopover.isShown else {
                return
            }
            finishReasoningMenuClose(for: reasoningPopover)
        }

        if let reasoningMenuPresentationOverride {
            reasoningMenuPresentationOverride()
            return
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

    func handleReasoningMenuPresentationRequestIfNeeded() {
        guard let configuration,
              let request = configuration.reasoningMenuPresentationRequest,
              handledReasoningMenuPresentationRequest != request else {
            return
        }
        if configuration.areControlsDisabled {
            consumeReasoningMenuPresentationRequest(request, configuration: configuration)
            return
        }
        guard window != nil else {
            return
        }

        handledReasoningMenuPresentationRequest = request
        window?.makeFirstResponder(reasoningButton)
        presentReasoningMenuIfNeeded()
        focusReasoningMenuEffortControl()
        notifyReasoningMenuRequestConsumed(request, configuration: configuration)
    }

    private func focusReasoningMenuEffortControl() {
        if let reasoningMenuEffortFocusOverride {
            reasoningMenuEffortFocusOverride()
            return
        }
        reasoningMenuController?.focusEffortControl()
    }

    private func consumeReasoningMenuPresentationRequest(
        _ request: UUID,
        configuration: Configuration
    ) {
        handledReasoningMenuPresentationRequest = request
        notifyReasoningMenuRequestConsumed(request, configuration: configuration)
    }

    private func notifyReasoningMenuRequestConsumed(
        _ request: UUID,
        configuration: Configuration
    ) {
        Task { @MainActor in
            configuration.onReasoningMenuRequestConsumed(request)
        }
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
