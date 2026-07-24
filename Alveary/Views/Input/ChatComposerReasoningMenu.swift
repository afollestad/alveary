import AppKit

@MainActor
final class ComposerReasoningMenuView: AppKitComposerPopoverSurfaceView {
    private var configuration: ChatComposerActionRowView.ReasoningConfiguration
    private let onEffortPreview: (Int) -> Void
    private let onEffortCommit: (Int) -> Void
    private let onEffortCancel: () -> Void
    private let onModelsExpansionChanged: (Bool) -> Void
    private let onModelSelected: (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void
    private let onFastModeChanged: (Bool) -> Void
    private let onCancel: () -> Void
    let effortSlider = ComposerReasoningEffortSlider()
    let modelsDisclosure: ComposerReasoningModelsDisclosureControl
    let fastToggle = ComposerReasoningFastToggleControl()
    let modelList: ComposerReasoningModelListView
    private let modelsSection = ComposerReasoningModelsSectionClipView()
    private let divider = AppKitComposerPopoverDividerView()
    private let fasterLabel = ComposerReasoningDragDirectionLabel(title: "Faster")
    private let smarterLabel = ComposerReasoningDragDirectionLabel(title: "Smarter")
    private(set) var isModelsExpanded: Bool
    private(set) var showsEffortDragDirections = false
    private var hasBuiltModelRows = false

    var hasActiveEffortInteraction: Bool { effortSlider.isTrackingInteraction }
    var preferredEffortFocusControl: NSView? { focusableControls.first }

    #if DEBUG
    var debugFasterLabel: NSTextField { fasterLabel }
    var debugSmarterLabel: NSTextField { smarterLabel }
    var debugModelsSection: ComposerReasoningModelsSectionClipView { modelsSection }
    #endif

    init(
        configuration: ChatComposerActionRowView.ReasoningConfiguration,
        isModelsExpanded: Bool,
        onEffortPreview: @escaping (Int) -> Void,
        onEffortCommit: @escaping (Int) -> Void,
        onEffortCancel: @escaping () -> Void,
        onModelsExpansionChanged: @escaping (Bool) -> Void,
        onModelSelected: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void,
        onFastModeChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void,
        reducesMotion: @escaping () -> Bool
    ) {
        self.configuration = configuration
        self.isModelsExpanded = isModelsExpanded
        self.onEffortPreview = onEffortPreview
        self.onEffortCommit = onEffortCommit
        self.onEffortCancel = onEffortCancel
        self.onModelsExpansionChanged = onModelsExpansionChanged
        self.onModelSelected = onModelSelected
        self.onFastModeChanged = onFastModeChanged
        self.onCancel = onCancel
        modelsDisclosure = ComposerReasoningModelsDisclosureControl(reducesMotion: reducesMotion)
        // Model rows are the menu's only expensive build (one custom view per
        // model per provider), so defer them until the disclosure first expands.
        hasBuiltModelRows = isModelsExpanded
        modelList = ComposerReasoningModelListView(
            groups: isModelsExpanded ? configuration.modelGroups : [],
            selectedProviderID: configuration.selection.providerID,
            selectedModelID: configuration.selection.modelID,
            onModelSelected: onModelSelected,
            onCancel: onCancel
        )
        super.init(frame: NSRect(
            origin: .zero,
            size: ComposerReasoningMenuMetrics.mainContentSize(
                for: configuration,
                isModelsExpanded: isModelsExpanded
            )
        ))
        setup()
        configureControls(animatedDisclosure: false)
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        configuration: ChatComposerActionRowView.ReasoningConfiguration,
        isModelsExpanded: Bool
    ) {
        self.configuration = configuration
        self.isModelsExpanded = isModelsExpanded
        if hasBuiltModelRows || isModelsExpanded {
            hasBuiltModelRows = true
            modelList.update(
                groups: configuration.modelGroups,
                selectedProviderID: configuration.selection.providerID,
                selectedModelID: configuration.selection.modelID
            )
        }
        configureControls(animatedDisclosure: false)
        frame.size = ComposerReasoningMenuMetrics.mainContentSize(
            for: configuration,
            isModelsExpanded: isModelsExpanded
        )
        needsLayout = true
    }

    func setModelsExpanded(_ isExpanded: Bool, animated: Bool) {
        if !isExpanded, let firstResponder = window?.firstResponder as? NSView,
           firstResponder === modelList || firstResponder.isReasoningMenuDescendant(of: modelList) {
            window?.makeFirstResponder(modelsDisclosure)
        }
        if isExpanded, !hasBuiltModelRows {
            // Build the deferred model rows synchronously before the resize
            // below so the expansion still sizes immediately, per the
            // no-animation disclosure contract.
            hasBuiltModelRows = true
            modelList.update(
                groups: configuration.modelGroups,
                selectedProviderID: configuration.selection.providerID,
                selectedModelID: configuration.selection.modelID
            )
        }
        self.isModelsExpanded = isExpanded
        if modelsDisclosure.isExpanded != isExpanded {
            modelsDisclosure.setExpanded(isExpanded, animated: animated)
        }
        configureModelsSectionSemantics()
        rebuildKeyViewLoop()
        needsLayout = true
    }

    func cancelEffortInteraction() {
        effortSlider.cancelInteraction(notify: false)
    }

    override func layout() {
        super.layout()
        var nextY = ComposerReasoningMenuMetrics.topInset
        if !effortSlider.isHidden {
            effortSlider.frame = NSRect(
                x: ComposerReasoningMenuMetrics.sliderHorizontalInset,
                y: nextY,
                width: bounds.width - ComposerReasoningMenuMetrics.sliderHorizontalInset * 2,
                height: ComposerReasoningMenuMetrics.sliderHeight
            )
            nextY += ComposerReasoningMenuMetrics.sliderHeight + ComposerReasoningMenuMetrics.sliderBottomSpacing
        } else {
            effortSlider.frame = .zero
        }

        nextY = layoutControlsRow(at: nextY)

        let sectionHeight = ComposerReasoningMenuMetrics.modelsSectionHeight(groups: configuration.modelGroups)
        let visibleSectionHeight = min(
            sectionHeight,
            max(0, bounds.height - nextY - ComposerReasoningMenuMetrics.bottomInset)
        )
        modelsSection.frame = NSRect(x: 0, y: nextY, width: bounds.width, height: visibleSectionHeight)
        divider.frame = NSRect(
            x: AppKitComposerPopoverDividerView.horizontalInset,
            y: ComposerReasoningMenuMetrics.dividerSpacing,
            width: bounds.width - AppKitComposerPopoverDividerView.horizontalInset * 2,
            height: AppKitComposerPopoverDividerView.height
        )
        modelList.frame = NSRect(
            x: 0,
            y: ComposerReasoningMenuMetrics.dividerSpacing +
                AppKitComposerPopoverDividerView.height +
                ComposerReasoningMenuMetrics.dividerSpacing,
            width: bounds.width,
            height: ComposerReasoningMenuMetrics.modelViewportHeight(groups: configuration.modelGroups)
        )
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }
        super.keyDown(with: event)
    }

    private func setup() {
        addSubview(effortSlider)
        addSubview(modelsDisclosure)
        addSubview(fastToggle)
        addSubview(fasterLabel)
        addSubview(smarterLabel)
        modelsSection.addSubview(divider)
        modelsSection.addSubview(modelList)
        addSubview(modelsSection)
    }

    private func layoutControlsRow(at originY: CGFloat) -> CGFloat {
        if showsEffortDragDirections {
            let fasterSize = fasterLabel.intrinsicContentSize
            let smarterSize = smarterLabel.intrinsicContentSize
            fasterLabel.frame = NSRect(
                x: ComposerReasoningMenuMetrics.sliderHorizontalInset,
                y: originY,
                width: fasterSize.width,
                height: ComposerReasoningMenuMetrics.controlsHeight
            )
            smarterLabel.frame = NSRect(
                x: bounds.maxX - ComposerReasoningMenuMetrics.sliderHorizontalInset - smarterSize.width,
                y: originY,
                width: smarterSize.width,
                height: ComposerReasoningMenuMetrics.controlsHeight
            )
            modelsDisclosure.frame = .zero
            fastToggle.frame = .zero
            return originY + ComposerReasoningMenuMetrics.controlsHeight
        }
        fasterLabel.frame = .zero
        smarterLabel.frame = .zero
        let fastWidth = fastToggle.isHidden ? 0 : fastToggle.intrinsicContentSize.width
        let fastSpacing: CGFloat = fastToggle.isHidden ? 0 : 6
        let fastTrailingInset = fastToggle.isHidden
            ? ComposerReasoningMenuMetrics.horizontalInset
            : ComposerReasoningMenuMetrics.sliderHorizontalInset - fastToggle.opticalTrailingPadding
        let availableModelsWidth = bounds.width - ComposerReasoningMenuMetrics.horizontalInset -
            fastTrailingInset - fastWidth - fastSpacing
        modelsDisclosure.frame = NSRect(
            x: ComposerReasoningMenuMetrics.horizontalInset,
            y: originY,
            width: max(0, availableModelsWidth),
            height: ComposerReasoningMenuMetrics.controlsHeight
        )
        if fastToggle.isHidden {
            fastToggle.frame = .zero
        } else {
            fastToggle.frame = NSRect(
                x: bounds.maxX - fastTrailingInset - fastWidth,
                y: originY + floor((ComposerReasoningMenuMetrics.controlsHeight - fastToggle.intrinsicContentSize.height) / 2),
                width: fastWidth,
                height: fastToggle.intrinsicContentSize.height
            )
        }
        return originY + ComposerReasoningMenuMetrics.controlsHeight
    }

    private func configureControls(animatedDisclosure: Bool) {
        let selectedIndex = configuration.selection.effortOptions.firstIndex {
            $0.value == configuration.selection.effortValue
        }
        let fallbackIndex = configuration.selection.defaultEffortValue.flatMap { defaultEffort in
            configuration.selection.effortOptions.firstIndex { $0.value == defaultEffort }
        } ?? 0
        effortSlider.configure(
            effortTitles: configuration.selection.effortOptions.map(\.title),
            selectedIndex: selectedIndex,
            fallbackIndex: fallbackIndex,
            isEnabled: true,
            onPreview: onEffortPreview,
            onCommit: onEffortCommit,
            onCancel: onEffortCancel,
            onDragDirectionVisibilityChanged: { [weak self] in self?.setEffortDragDirectionsVisible($0) }
        )
        modelsDisclosure.configure(
            isExpanded: isModelsExpanded,
            isEnabled: true,
            animated: animatedDisclosure,
            onExpansionChange: onModelsExpansionChanged
        )
        modelsDisclosure.isHidden = showsEffortDragDirections
        fastToggle.isHidden = showsEffortDragDirections || !configuration.selection.supportsSpeedMode
        fastToggle.configure(
            isOn: configuration.selection.speedMode == .fast,
            isEnabled: configuration.selection.supportsSpeedMode,
            onToggle: onFastModeChanged
        )
        configureModelsSectionSemantics()
        rebuildKeyViewLoop()
    }

    private func configureModelsSectionSemantics() {
        modelsSection.allowsHitTesting = isModelsExpanded
        modelsSection.setAccessibilityHidden(!isModelsExpanded)
    }

    private func rebuildKeyViewLoop() {
        let controls = focusableControls
        guard let first = controls.first else { return }
        for (index, control) in controls.enumerated() {
            control.nextKeyView = controls[reasoningMenuSafe: index + 1] ?? first
        }
    }

    private var focusableControls: [NSView] {
        var controls: [NSView] = []
        if effortSlider.acceptsFirstResponder {
            controls.append(effortSlider)
        }
        if !modelsDisclosure.isHidden, modelsDisclosure.acceptsFirstResponder {
            controls.append(modelsDisclosure)
        }
        if !fastToggle.isHidden, fastToggle.acceptsFirstResponder {
            controls.append(fastToggle)
        }
        if isModelsExpanded {
            controls.append(contentsOf: modelList.focusableRows)
        }
        return controls
    }

    private func setEffortDragDirectionsVisible(_ isVisible: Bool) {
        guard showsEffortDragDirections != isVisible else {
            return
        }
        showsEffortDragDirections = isVisible
        fasterLabel.isHidden = !isVisible
        smarterLabel.isHidden = !isVisible
        modelsDisclosure.isHidden = isVisible
        fastToggle.isHidden = isVisible || !configuration.selection.supportsSpeedMode
        rebuildKeyViewLoop()
        needsLayout = true
        layoutSubtreeIfNeeded()
    }
}
