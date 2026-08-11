@preconcurrency import AppKit

extension ChatComposerActionRowView {
    static let reasoningPopoverPreferredEdge = ComposerReasoningMenuPresenter.preferredEdge

    /// Forwarding onto the shared presenter. These stay settable because tests install a recording
    /// popover and controller rather than showing a live one.
    var reasoningPopover: NSPopover? {
        get { reasoningMenuPresenter.popover }
        set { reasoningMenuPresenter.popover = newValue }
    }

    var reasoningMenuController: ComposerReasoningMenuViewController? {
        get { reasoningMenuPresenter.controller }
        set { reasoningMenuPresenter.controller = newValue }
    }

    var reasoningPopoverAnchorRect: NSRect? {
        get { reasoningMenuPresenter.anchorRect }
        set {
            reasoningMenuPresenter.anchorRect = newValue
            // The row is always its own positioning view; keep the two set together so a resize can
            // reapply the captured anchor.
            reasoningMenuPresenter.anchorView = newValue == nil ? nil : self
        }
    }

    var reasoningMenuIsPresentedOverride: (() -> Bool)? {
        get { reasoningMenuPresenter.isPresentedOverride }
        set { reasoningMenuPresenter.isPresentedOverride = newValue }
    }

    var reasoningMenuPresentationOverride: (() -> Void)? {
        get { reasoningMenuPresenter.presentationOverride }
        set { reasoningMenuPresenter.presentationOverride = newValue }
    }

    var reasoningMenuEffortFocusOverride: (() -> Void)? {
        get { reasoningMenuPresenter.effortFocusOverride }
        set { reasoningMenuPresenter.effortFocusOverride = newValue }
    }

    var reasoningMenuModelsFocusOverride: (() -> Void)? {
        get { reasoningMenuPresenter.modelsFocusOverride }
        set { reasoningMenuPresenter.modelsFocusOverride = newValue }
    }

    /// Which reasoning control a programmatic presentation should open on, so `/effort` and `/model` land in place.
    enum ReasoningMenuSection: Equatable {
        case effort
        case models
    }

    struct ReasoningMenuPresentationRequest: Equatable {
        let id: UUID
        let section: ReasoningMenuSection

        init(id: UUID = UUID(), section: ReasoningMenuSection) {
            self.id = id
            self.section = section
        }
    }

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
        if reasoningMenuPresenter.isShown {
            closeReasoningMenu()
            return
        }

        presentReasoningMenuIfNeeded()
    }

    func presentReasoningMenuIfNeeded() {
        guard let configuration,
              !configuration.areControlsDisabled else {
            closeReasoningMenu()
            return
        }

        reasoningMenuPresenter.present(
            configuration: configuration.reasoning,
            anchorView: self,
            anchorRect: captureReasoningPopoverAnchorRect()
        )
    }

    func handleReasoningMenuPresentationRequestIfNeeded() {
        guard let configuration,
              let request = configuration.reasoningMenuPresentationRequest,
              handledReasoningMenuPresentationRequest != request.id else {
            return
        }
        if configuration.areControlsDisabled {
            consumeReasoningMenuPresentationRequest(request.id, configuration: configuration)
            return
        }
        guard window != nil else {
            return
        }

        handledReasoningMenuPresentationRequest = request.id
        window?.makeFirstResponder(reasoningButton)
        presentReasoningMenuIfNeeded()
        switch request.section {
        case .effort:
            focusReasoningMenuEffortControl()
        case .models:
            revealReasoningMenuModelList()
        }
        notifyReasoningMenuRequestConsumed(request.id, configuration: configuration)
    }

    private func focusReasoningMenuEffortControl() {
        reasoningMenuPresenter.focusEffortControl()
    }

    private func revealReasoningMenuModelList() {
        reasoningMenuPresenter.focusModelList()
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
        reasoningMenuPresenter.close()
    }

    func captureReasoningPopoverAnchorRect() -> NSRect {
        reasoningButton.convert(reasoningButton.bounds, to: self)
    }

    func applyReasoningPopoverContentSize(_ size: NSSize) {
        reasoningMenuPresenter.applyContentSize(size)
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
