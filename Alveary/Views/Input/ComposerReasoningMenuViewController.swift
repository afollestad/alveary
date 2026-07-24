import AppKit

@MainActor
final class ComposerReasoningMenuViewController: NSViewController {
    private var configuration: ChatComposerActionRowView.ReasoningConfiguration
    private let onRequestCloseMainMenu: () -> Void
    private let onDisplaySelectionChanged: (ChatComposerActionRowView.ReasoningSelection?) -> Void
    private let onContentSizeChanged: (NSSize) -> Void
    private let reducesMotion: () -> Bool
    private var menuView: ComposerReasoningMenuView?
    private var previewSelection: ChatComposerActionRowView.ReasoningSelection?
    private var hasDisplaySelectionOverride = false
    private(set) var isModelsExpanded = false

    init(
        configuration: ChatComposerActionRowView.ReasoningConfiguration,
        onRequestCloseMainMenu: @escaping () -> Void,
        onDisplaySelectionChanged: @escaping (ChatComposerActionRowView.ReasoningSelection?) -> Void = { _ in },
        onContentSizeChanged: @escaping (NSSize) -> Void = { _ in },
        reducesMotion: @escaping () -> Bool = { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }
    ) {
        self.configuration = configuration
        self.onRequestCloseMainMenu = onRequestCloseMainMenu
        self.onDisplaySelectionChanged = onDisplaySelectionChanged
        self.onContentSizeChanged = onContentSizeChanged
        self.reducesMotion = reducesMotion
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerReasoningMenuMetrics.mainContentSize(for: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let menuView = ComposerReasoningMenuView(
            configuration: configuration,
            isModelsExpanded: isModelsExpanded,
            onEffortPreview: { [weak self] in self?.previewEffort(at: $0) },
            onEffortCommit: { [weak self] in self?.commitEffort(at: $0) },
            onEffortCancel: { [weak self] in self?.cancelEffortPreview(requestClose: true) },
            onModelsExpansionChanged: { [weak self] in self?.setModelsExpanded($0, animated: true) },
            onModelSelected: { [weak self] in self?.selectModel($0) },
            onFastModeChanged: { [weak self] in self?.selectFastMode(isEnabled: $0) },
            onCancel: { [weak self] in self?.requestClose() },
            reducesMotion: reducesMotion
        )
        self.menuView = menuView
        menuView.autoresizingMask = [.width, .height]
        view = menuView
    }

    func update(configuration: ChatComposerActionRowView.ReasoningConfiguration) {
        let previousVisualState = ReasoningMenuVisualState(configuration: self.configuration)
        let visualState = ReasoningMenuVisualState(configuration: configuration)
        let preservesActivePreview = menuView?.hasActiveEffortInteraction == true &&
            previousVisualState == visualState

        if !preservesActivePreview {
            cancelEffortPreview()
        }
        self.configuration = configuration

        guard previousVisualState != visualState else { return }
        menuView?.update(configuration: configuration, isModelsExpanded: isModelsExpanded)
        applyContentSize()
    }

    func setModelsExpanded(_ isExpanded: Bool, animated: Bool = false) {
        guard isModelsExpanded != isExpanded else { return }
        isModelsExpanded = isExpanded
        menuView?.setModelsExpanded(isExpanded, animated: animated)
        applyContentSize()
    }

    func selectModel(_ request: ChatComposerActionRowView.ReasoningModelSelectionRequest) {
        cancelEffortPreview()
        switch configuration.onModelChange(request) {
        case .rejected:
            menuView?.update(configuration: configuration, isModelsExpanded: isModelsExpanded)
            onDisplaySelectionChanged(nil)
            onRequestCloseMainMenu()
        case .unchanged(let selection), .applied(let selection):
            applyLocallyAcceptedSelection(selection)
        }
    }

    func cancelEffortPreview() {
        cancelEffortPreview(requestClose: false)
    }

    func alignContentViewToPopoverHost() {
        applyLoadedContentFrame(size: preferredContentSize)
    }

    #if DEBUG
    var debugEffortSlider: ComposerReasoningEffortSlider? { menuView?.effortSlider }
    var debugModelsDisclosure: ComposerReasoningModelsDisclosureControl? { menuView?.modelsDisclosure }
    var debugFastToggle: ComposerReasoningFastToggleControl? { menuView?.fastToggle }
    var debugModelList: ComposerReasoningModelListView? { menuView?.modelList }
    var debugModelsSection: ComposerReasoningModelsSectionClipView? { menuView?.debugModelsSection }
    var debugShowsEffortDragDirections: Bool { menuView?.showsEffortDragDirections == true }
    var debugFasterLabel: NSTextField? { menuView?.debugFasterLabel }
    var debugSmarterLabel: NSTextField? { menuView?.debugSmarterLabel }
    #endif

    private func previewEffort(at index: Int) {
        guard let option = configuration.selection.effortOptions[reasoningMenuSafe: index] else {
            return
        }
        let selection = configuration.selection.updatingEffort(option)
        previewSelection = selection
        hasDisplaySelectionOverride = true
        onDisplaySelectionChanged(selection)
    }

    private func commitEffort(at index: Int) {
        guard let option = configuration.selection.effortOptions[reasoningMenuSafe: index] else {
            cancelEffortPreview(requestClose: true)
            return
        }
        let selection = configuration.selection.updatingEffort(option)
        guard configuration.onEffortChange(option.value) else {
            previewSelection = nil
            hasDisplaySelectionOverride = false
            menuView?.update(configuration: configuration, isModelsExpanded: isModelsExpanded)
            onDisplaySelectionChanged(nil)
            onRequestCloseMainMenu()
            return
        }
        previewSelection = nil
        applyLocallyAcceptedSelection(selection)
    }

    private func selectFastMode(isEnabled: Bool) {
        cancelEffortPreview()
        let speedMode: AgentSpeedMode = isEnabled ? .fast : .standard
        guard configuration.onSpeedChange(speedMode) else {
            menuView?.update(configuration: configuration, isModelsExpanded: isModelsExpanded)
            onDisplaySelectionChanged(nil)
            onRequestCloseMainMenu()
            return
        }
        applyLocallyAcceptedSelection(configuration.selection.updatingSpeedMode(speedMode))
    }

    private func applyLocallyAcceptedSelection(_ selection: ChatComposerActionRowView.ReasoningSelection) {
        configuration.selection = selection
        previewSelection = nil
        hasDisplaySelectionOverride = true
        onDisplaySelectionChanged(selection)
        menuView?.update(configuration: configuration, isModelsExpanded: isModelsExpanded)
        applyContentSize()
    }

    private func cancelEffortPreview(requestClose: Bool) {
        menuView?.cancelEffortInteraction()
        let shouldClearDisplaySelection = previewSelection != nil || hasDisplaySelectionOverride
        previewSelection = nil
        hasDisplaySelectionOverride = false
        if shouldClearDisplaySelection {
            onDisplaySelectionChanged(nil)
        }
        if requestClose {
            onRequestCloseMainMenu()
        }
    }

    private func requestClose() {
        cancelEffortPreview()
        onRequestCloseMainMenu()
    }

    private func applyContentSize() {
        let size = ComposerReasoningMenuMetrics.mainContentSize(for: configuration, isModelsExpanded: isModelsExpanded)
        guard preferredContentSize != size else {
            menuView?.frame.size = size
            menuView?.needsLayout = true
            return
        }
        preferredContentSize = size
        onContentSizeChanged(size)
        applyLoadedContentFrame(size: size)
        Task { @MainActor [weak self] in
            await Task.yield()
            guard let self, preferredContentSize == size else { return }
            applyLoadedContentFrame(size: size)
        }
    }

    private func applyLoadedContentFrame(size: NSSize) {
        guard isViewLoaded else { return }
        view.frame = ComposerReasoningPopoverContentFrame.topAlignedFrame(for: view, size: size)
        view.layoutSubtreeIfNeeded()
    }
}
