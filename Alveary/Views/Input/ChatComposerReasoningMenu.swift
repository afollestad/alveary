import AppKit

@MainActor
final class ComposerReasoningMenuViewController: NSViewController {
    private var configuration: ChatComposerActionRowView.ReasoningConfiguration
    private let onRequestCloseMainMenu: () -> Void
    private var menuView: ComposerReasoningMenuView?
    private var modelPopover: NSPopover?
    private var modelMenuController: ComposerReasoningModelMenuViewController?
    private var speedPopover: NSPopover?
    private var speedMenuController: ComposerReasoningSpeedMenuViewController?
    private var closeModelMenuTask: Task<Void, Never>?
    private var closeSpeedMenuTask: Task<Void, Never>?
    private var isModelRowHovered = false
    private var isModelMenuHovered = false
    private var isSpeedRowHovered = false
    private var isSpeedMenuHovered = false

    init(
        configuration: ChatComposerActionRowView.ReasoningConfiguration,
        onRequestCloseMainMenu: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onRequestCloseMainMenu = onRequestCloseMainMenu
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerReasoningMenuMetrics.mainContentSize(for: configuration)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let menuView = ComposerReasoningMenuView(
            configuration: configuration,
            onEffortSelected: { [weak self] effort in
                self?.selectEffort(effort)
            },
            onModelMenuRequested: { [weak self] anchor in
                self?.showModelMenu(relativeTo: anchor)
            },
            onModelRowHoverChanged: { [weak self] isHovering, anchor in
                self?.setModelRowHovered(isHovering, relativeTo: anchor)
            },
            onSpeedMenuRequested: { [weak self] anchor in
                self?.showSpeedMenu(relativeTo: anchor)
            },
            onSpeedRowHoverChanged: { [weak self] isHovering, anchor in
                self?.setSpeedRowHovered(isHovering, relativeTo: anchor)
            },
            onCancel: { [weak self] in
                self?.onRequestCloseMainMenu()
            }
        )
        self.menuView = menuView
        view = menuView
    }

    func update(configuration: ChatComposerActionRowView.ReasoningConfiguration) {
        self.configuration = configuration
        let size = ComposerReasoningMenuMetrics.mainContentSize(for: configuration)
        preferredContentSize = size
        menuView?.update(configuration: configuration)
        modelMenuController?.update(
            groups: configuration.modelGroups,
            selectedProviderID: configuration.selection.providerID,
            selectedModelID: configuration.selection.modelID,
            showsProviderHeaders: !configuration.hasStartedThread
        )
        speedMenuController?.update(selectedSpeedMode: configuration.selection.speedMode)
        if !configuration.selection.supportsSpeedMode {
            closeSpeedMenu()
        }
    }

    func closeModelMenu() {
        closeModelMenuTask?.cancel()
        closeModelMenuTask = nil
        isModelRowHovered = false
        isModelMenuHovered = false
        modelPopover?.performClose(nil)
        modelPopover = nil
        modelMenuController = nil
    }

    func closeSpeedMenu() {
        closeSpeedMenuTask?.cancel()
        closeSpeedMenuTask = nil
        isSpeedRowHovered = false
        isSpeedMenuHovered = false
        speedPopover?.performClose(nil)
        speedPopover = nil
        speedMenuController = nil
    }

    private func selectEffort(_ effort: String) {
        guard configuration.onEffortChange(effort) else {
            onRequestCloseMainMenu()
            return
        }
        onRequestCloseMainMenu()
    }

    private func showModelMenu(relativeTo anchor: NSView) {
        closeSpeedMenu()
        if modelPopover?.isShown == true {
            modelMenuController?.update(
                groups: configuration.modelGroups,
                selectedProviderID: configuration.selection.providerID,
                selectedModelID: configuration.selection.modelID,
                showsProviderHeaders: !configuration.hasStartedThread
            )
            return
        }

        let controller = ComposerReasoningModelMenuViewController(
            groups: configuration.modelGroups,
            selectedProviderID: configuration.selection.providerID,
            selectedModelID: configuration.selection.modelID,
            showsProviderHeaders: !configuration.hasStartedThread,
            onModelSelected: { [weak self] request in
                self?.selectModel(request)
            },
            onHoverChanged: { [weak self] isHovering in
                self?.setModelMenuHovered(isHovering)
            },
            onCancel: { [weak self] in
                self?.closeModelMenu()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
        modelMenuController = controller
        modelPopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    private func showSpeedMenu(relativeTo anchor: NSView) {
        guard configuration.selection.supportsSpeedMode else {
            return
        }
        closeModelMenu()
        if speedPopover?.isShown == true {
            speedMenuController?.update(selectedSpeedMode: configuration.selection.speedMode)
            return
        }

        let controller = ComposerReasoningSpeedMenuViewController(
            selectedSpeedMode: configuration.selection.speedMode,
            onSpeedSelected: { [weak self] speedMode in
                self?.selectSpeedMode(speedMode)
            },
            onHoverChanged: { [weak self] isHovering in
                self?.setSpeedMenuHovered(isHovering)
            },
            onCancel: { [weak self] in
                self?.closeSpeedMenu()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.contentViewController = controller
        speedMenuController = controller
        speedPopover = popover
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxX)
    }

    func selectModel(_ request: ChatComposerActionRowView.ReasoningModelSelectionRequest) {
        switch configuration.onModelChange(request) {
        case .rejected:
            closeModelMenu()
            onRequestCloseMainMenu()
        case .unchanged(let selection):
            configuration.selection = selection
            closeModelMenu()
            update(configuration: configuration)
        case .applied(let selection):
            configuration.selection = selection
            update(configuration: configuration)
            // Model selections close only the drill-in submenu. The main popup
            // stays open so the selected model's reasoning default remains visible.
            closeModelMenu()
        }
    }

    private func selectSpeedMode(_ speedMode: AgentSpeedMode) {
        guard configuration.onSpeedChange(speedMode) else {
            closeSpeedMenu()
            onRequestCloseMainMenu()
            return
        }
        configuration.selection = ChatComposerActionRowView.ReasoningSelection(
            providerID: configuration.selection.providerID,
            providerTitle: configuration.selection.providerTitle,
            modelID: configuration.selection.modelID,
            modelTitle: configuration.selection.modelTitle,
            effortValue: configuration.selection.effortValue,
            effortTitle: configuration.selection.effortTitle,
            effortOptions: configuration.selection.effortOptions,
            speedMode: speedMode,
            supportsSpeedMode: configuration.selection.supportsSpeedMode
        )
        closeSpeedMenu()
        onRequestCloseMainMenu()
    }

    private func setModelRowHovered(_ isHovering: Bool, relativeTo anchor: NSView) {
        isModelRowHovered = isHovering
        if isHovering {
            closeModelMenuTask?.cancel()
            closeModelMenuTask = nil
            showModelMenu(relativeTo: anchor)
        } else {
            scheduleModelMenuCloseIfNeeded()
        }
    }

    private func setSpeedRowHovered(_ isHovering: Bool, relativeTo anchor: NSView) {
        isSpeedRowHovered = isHovering
        if isHovering {
            closeSpeedMenuTask?.cancel()
            closeSpeedMenuTask = nil
            showSpeedMenu(relativeTo: anchor)
        } else {
            scheduleSpeedMenuCloseIfNeeded()
        }
    }

    private func setModelMenuHovered(_ isHovering: Bool) {
        isModelMenuHovered = isHovering
        if isHovering {
            closeModelMenuTask?.cancel()
            closeModelMenuTask = nil
        } else {
            scheduleModelMenuCloseIfNeeded()
        }
    }

    private func setSpeedMenuHovered(_ isHovering: Bool) {
        isSpeedMenuHovered = isHovering
        if isHovering {
            closeSpeedMenuTask?.cancel()
            closeSpeedMenuTask = nil
        } else {
            scheduleSpeedMenuCloseIfNeeded()
        }
    }

    private func scheduleModelMenuCloseIfNeeded() {
        closeModelMenuTask?.cancel()
        closeModelMenuTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self,
                  !isModelRowHovered,
                  !isModelMenuHovered else {
                return
            }
            closeModelMenu()
        }
    }

    private func scheduleSpeedMenuCloseIfNeeded() {
        closeSpeedMenuTask?.cancel()
        closeSpeedMenuTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 120_000_000)
            guard let self,
                  !isSpeedRowHovered,
                  !isSpeedMenuHovered else {
                return
            }
            closeSpeedMenu()
        }
    }
}

@MainActor
private final class ComposerReasoningMenuView: AppKitComposerPopoverSurfaceView {
    private var configuration: ChatComposerActionRowView.ReasoningConfiguration
    private let onEffortSelected: (String) -> Void
    private let onModelMenuRequested: (NSView) -> Void
    private let onModelRowHoverChanged: (Bool, NSView) -> Void
    private let onSpeedMenuRequested: (NSView) -> Void
    private let onSpeedRowHoverChanged: (Bool, NSView) -> Void
    private let onCancel: () -> Void
    private let headerField = ComposerReasoningHeaderView(title: "Reasoning")
    private let modelHeaderField = ComposerReasoningHeaderView(title: "Model")
    private let divider = AppKitComposerPopoverDividerView()
    private let modelRow = ComposerReasoningMenuRowView()
    private let speedRow = ComposerReasoningMenuRowView()
    private var effortRows: [ComposerReasoningMenuRowView] = []

    init(
        configuration: ChatComposerActionRowView.ReasoningConfiguration,
        onEffortSelected: @escaping (String) -> Void,
        onModelMenuRequested: @escaping (NSView) -> Void,
        onModelRowHoverChanged: @escaping (Bool, NSView) -> Void,
        onSpeedMenuRequested: @escaping (NSView) -> Void,
        onSpeedRowHoverChanged: @escaping (Bool, NSView) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onEffortSelected = onEffortSelected
        self.onModelMenuRequested = onModelMenuRequested
        self.onModelRowHoverChanged = onModelRowHoverChanged
        self.onSpeedMenuRequested = onSpeedMenuRequested
        self.onSpeedRowHoverChanged = onSpeedRowHoverChanged
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: ComposerReasoningMenuMetrics.mainContentSize(for: configuration)))
        setup()
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(configuration: ChatComposerActionRowView.ReasoningConfiguration) {
        self.configuration = configuration
        frame.size = ComposerReasoningMenuMetrics.mainContentSize(for: configuration)
        rebuildRows()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var nextY = ComposerReasoningMenuMetrics.verticalInset
        headerField.frame = NSRect(
            x: ComposerReasoningMenuMetrics.headerInset,
            y: nextY,
            width: bounds.width - ComposerReasoningMenuMetrics.headerInset * 2,
            height: ComposerReasoningMenuMetrics.headerHeight
        )
        nextY += ComposerReasoningMenuMetrics.headerHeight + ComposerReasoningMenuMetrics.headerBottomSpacing
        if !configuration.selection.effortOptions.isEmpty {
            for row in effortRows {
                row.frame = NSRect(
                    x: ComposerReasoningMenuMetrics.horizontalInset,
                    y: nextY,
                    width: bounds.width - ComposerReasoningMenuMetrics.horizontalInset * 2,
                    height: ComposerReasoningMenuMetrics.rowHeight
                )
                nextY += ComposerReasoningMenuMetrics.rowHeight
            }
            nextY += ComposerReasoningMenuMetrics.dividerSpacing
            divider.frame = NSRect(
                x: AppKitComposerPopoverDividerView.horizontalInset,
                y: nextY,
                width: bounds.width - AppKitComposerPopoverDividerView.horizontalInset * 2,
                height: AppKitComposerPopoverDividerView.height
            )
            nextY += AppKitComposerPopoverDividerView.height + ComposerReasoningMenuMetrics.dividerSpacing
        }
        modelHeaderField.frame = NSRect(
            x: ComposerReasoningMenuMetrics.headerInset,
            y: nextY,
            width: bounds.width - ComposerReasoningMenuMetrics.headerInset * 2,
            height: ComposerReasoningMenuMetrics.headerHeight
        )
        nextY += ComposerReasoningMenuMetrics.headerHeight + ComposerReasoningMenuMetrics.headerBottomSpacing

        modelRow.frame = NSRect(
            x: ComposerReasoningMenuMetrics.horizontalInset,
            y: nextY,
            width: bounds.width - ComposerReasoningMenuMetrics.horizontalInset * 2,
            height: ComposerReasoningMenuMetrics.rowHeight
        )
        nextY += ComposerReasoningMenuMetrics.rowHeight

        if configuration.selection.supportsSpeedMode {
            speedRow.frame = NSRect(
                x: ComposerReasoningMenuMetrics.horizontalInset,
                y: nextY,
                width: bounds.width - ComposerReasoningMenuMetrics.horizontalInset * 2,
                height: ComposerReasoningMenuMetrics.rowHeight
            )
        }
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }
        super.keyDown(with: event)
    }

    private func setup() {
        // Match the context-window tooltip instead of the system material so
        // composer popovers read as one family.
        headerField.setAccessibilityElement(false)
        addSubview(headerField)
        modelHeaderField.setAccessibilityElement(false)
        addSubview(modelHeaderField)

        addSubview(divider)
        addSubview(modelRow)
        addSubview(speedRow)
    }

    private func rebuildRows() {
        effortRows.forEach { $0.removeFromSuperview() }
        effortRows = configuration.selection.effortOptions.map(makeEffortRow(option:))

        divider.isHidden = configuration.selection.effortOptions.isEmpty
        configureModelRow()
        configureSpeedRow()
    }

    private func makeEffortRow(option: ChatComposerActionRowView.MenuOption) -> ComposerReasoningMenuRowView {
        let row = ComposerReasoningMenuRowView()
        row.configure(.init(
            title: option.title,
            iconName: nil,
            trailingIconName: option.value == configuration.selection.effortValue ? "checkmark" : nil,
            accessibilityLabel: option.title,
            isSelected: option.value == configuration.selection.effortValue,
            isEnabled: true,
            action: { [weak self] in self?.onEffortSelected(option.value) },
            hoverAction: nil,
            cancelAction: { [weak self] in self?.onCancel() }
        ))
        addSubview(row)
        return row
    }

    private func configureModelRow() {
        modelRow.configure(.init(
            title: configuration.selection.modelTitle,
            iconName: nil,
            trailingIconName: "chevron.right",
            accessibilityLabel: "Model",
            isSelected: false,
            isEnabled: true,
            action: { [weak self, weak modelRow] in
                guard let modelRow else { return }
                self?.onModelMenuRequested(modelRow)
            },
            hoverAction: { [weak self, weak modelRow] in
                guard let modelRow else { return }
                self?.onModelMenuRequested(modelRow)
            },
            exitAction: { [weak self, weak modelRow] in
                guard let modelRow else { return }
                self?.onModelRowHoverChanged(false, modelRow)
            },
            cancelAction: { [weak self] in self?.onCancel() }
        ))
        modelRow.onHoverEntered = { [weak self, weak modelRow] in
            guard let modelRow else { return }
            self?.onModelRowHoverChanged(true, modelRow)
        }
    }

    private func configureSpeedRow() {
        speedRow.isHidden = !configuration.selection.supportsSpeedMode
        guard configuration.selection.supportsSpeedMode else {
            speedRow.onHoverEntered = nil
            return
        }
        speedRow.configure(.init(
            title: "Speed",
            iconName: nil,
            trailingIconName: "chevron.right",
            accessibilityLabel: "Speed, \(configuration.selection.speedMode.title)",
            isSelected: false,
            isEnabled: true,
            action: { [weak self, weak speedRow] in
                guard let speedRow else { return }
                self?.onSpeedMenuRequested(speedRow)
            },
            hoverAction: { [weak self, weak speedRow] in
                guard let speedRow else { return }
                self?.onSpeedMenuRequested(speedRow)
            },
            exitAction: { [weak self, weak speedRow] in
                guard let speedRow else { return }
                self?.onSpeedRowHoverChanged(false, speedRow)
            },
            cancelAction: { [weak self] in self?.onCancel() }
        ))
        speedRow.onHoverEntered = { [weak self, weak speedRow] in
            guard let speedRow else { return }
            self?.onSpeedRowHoverChanged(true, speedRow)
        }
    }
}
