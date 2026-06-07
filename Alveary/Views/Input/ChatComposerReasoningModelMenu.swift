import AppKit

@MainActor
final class ComposerReasoningModelMenuViewController: NSViewController {
    private var groups: [ChatComposerActionRowView.ReasoningModelGroup]
    private var selectedProviderID: String
    private var selectedModelID: String
    private var showsProviderHeaders: Bool
    private let onModelSelected: (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void
    private let onHoverChanged: (Bool) -> Void
    private let onCancel: () -> Void
    private var modelView: ComposerReasoningModelMenuView?

    init(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        selectedProviderID: String,
        selectedModelID: String,
        showsProviderHeaders: Bool,
        onModelSelected: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void,
        onHoverChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groups = groups
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.showsProviderHeaders = showsProviderHeaders
        self.onModelSelected = onModelSelected
        self.onHoverChanged = onHoverChanged
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerReasoningMenuMetrics.modelContentSize(
            groups: groups,
            showsProviderHeaders: showsProviderHeaders
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let modelView = ComposerReasoningModelMenuView(
            groups: groups,
            selectedProviderID: selectedProviderID,
            selectedModelID: selectedModelID,
            showsProviderHeaders: showsProviderHeaders,
            onModelSelected: onModelSelected,
            onHoverChanged: onHoverChanged,
            onCancel: onCancel
        )
        self.modelView = modelView
        view = modelView
    }

    func update(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        selectedProviderID: String,
        selectedModelID: String,
        showsProviderHeaders: Bool
    ) {
        self.groups = groups
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.showsProviderHeaders = showsProviderHeaders
        preferredContentSize = ComposerReasoningMenuMetrics.modelContentSize(
            groups: groups,
            showsProviderHeaders: showsProviderHeaders
        )
        modelView?.update(
            groups: groups,
            selectedProviderID: selectedProviderID,
            selectedModelID: selectedModelID,
            showsProviderHeaders: showsProviderHeaders
        )
    }
}

@MainActor
private final class ComposerReasoningModelMenuView: AppKitComposerPopoverSurfaceView {
    private var groups: [ChatComposerActionRowView.ReasoningModelGroup]
    private var selectedProviderID: String
    private var selectedModelID: String
    private var showsProviderHeaders: Bool
    private let onModelSelected: (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void
    private let onHoverChanged: (Bool) -> Void
    private let onCancel: () -> Void
    private let scrollView = NSScrollView()
    private let documentView = ComposerReasoningModelDocumentView()
    private var rowViews: [NSView] = []
    private var trackingArea: NSTrackingArea?

    init(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        selectedProviderID: String,
        selectedModelID: String,
        showsProviderHeaders: Bool,
        onModelSelected: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void,
        onHoverChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groups = groups
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.showsProviderHeaders = showsProviderHeaders
        self.onModelSelected = onModelSelected
        self.onHoverChanged = onHoverChanged
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: ComposerReasoningMenuMetrics.modelContentSize(
            groups: groups,
            showsProviderHeaders: showsProviderHeaders
        )))
        setup()
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        selectedProviderID: String,
        selectedModelID: String,
        showsProviderHeaders: Bool
    ) {
        self.groups = groups
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.showsProviderHeaders = showsProviderHeaders
        frame.size = ComposerReasoningMenuMetrics.modelContentSize(
            groups: groups,
            showsProviderHeaders: showsProviderHeaders
        )
        rebuildRows()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutRows()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = area
        addTrackingArea(area)
    }

    override func mouseEntered(with event: NSEvent) {
        onHoverChanged(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHoverChanged(false)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onCancel()
            return
        }
        super.keyDown(with: event)
    }

    private func setup() {
        // Match the context-window tooltip surface; the scroll view stays clear
        // so long model lists do not introduce a second fill color.
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    private func rebuildRows() {
        rowViews.forEach { $0.removeFromSuperview() }
        rowViews = []

        if groups.flatMap(\.options).isEmpty {
            let row = ComposerReasoningMenuRowView()
            row.configure(.init(
                title: "No models available",
                iconName: nil,
                trailingIconName: nil,
                accessibilityLabel: "No models available",
                isSelected: false,
                isEnabled: false,
                action: {},
                hoverAction: nil,
                cancelAction: onCancel
            ))
            rowViews.append(row)
            documentView.addSubview(row)
            return
        }

        for (groupIndex, group) in groups.enumerated() {
            if showsProviderHeaders, let providerTitle = group.providerTitle {
                let header = ComposerReasoningHeaderView(title: providerTitle)
                rowViews.append(header)
                documentView.addSubview(header)
            }

            for option in group.options {
                let row = ComposerReasoningMenuRowView()
                let isSelected = option.providerID == selectedProviderID && option.value == selectedModelID
                row.configure(.init(
                    title: option.title,
                    iconName: nil,
                    trailingIconName: isSelected ? "checkmark" : nil,
                    accessibilityLabel: option.title,
                    isSelected: isSelected,
                    isEnabled: true,
                    action: { [weak self] in
                        self?.onModelSelected(.init(providerID: option.providerID, modelID: option.value))
                    },
                    hoverAction: nil,
                    cancelAction: onCancel
                ))
                rowViews.append(row)
                documentView.addSubview(row)
            }

            if showsProviderHeaders, groupIndex < groups.count - 1 {
                let divider = AppKitComposerPopoverDividerView()
                rowViews.append(divider)
                documentView.addSubview(divider)
            }
        }
    }

    private func layoutRows() {
        let contentHeight = ComposerReasoningMenuMetrics.modelDocumentHeight(
            groups: groups,
            showsProviderHeaders: showsProviderHeaders
        )
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(bounds.height, contentHeight)
        )

        var nextY = ComposerReasoningMenuMetrics.verticalInset
        for rowView in rowViews {
            let height: CGFloat
            let originX: CGFloat
            let width: CGFloat
            if rowView is ComposerReasoningHeaderView {
                height = ComposerReasoningMenuMetrics.headerHeight
                originX = ComposerReasoningMenuMetrics.headerInset
                width = documentView.bounds.width - ComposerReasoningMenuMetrics.headerInset * 2
            } else if rowView is AppKitComposerPopoverDividerView {
                height = AppKitComposerPopoverDividerView.height
                originX = AppKitComposerPopoverDividerView.horizontalInset
                width = documentView.bounds.width - AppKitComposerPopoverDividerView.horizontalInset * 2
            } else {
                height = ComposerReasoningMenuMetrics.rowHeight
                originX = ComposerReasoningMenuMetrics.horizontalInset
                width = documentView.bounds.width - ComposerReasoningMenuMetrics.horizontalInset * 2
            }
            rowView.frame = NSRect(x: originX, y: nextY, width: width, height: height)
            if rowView is AppKitComposerPopoverDividerView {
                rowView.frame.origin.y += ComposerReasoningMenuMetrics.dividerSpacing
                nextY += height + ComposerReasoningMenuMetrics.dividerSpacing * 2
            } else if rowView is ComposerReasoningHeaderView {
                nextY += height + ComposerReasoningMenuMetrics.headerBottomSpacing
            } else {
                nextY += height
            }
        }
    }
}

private final class ComposerReasoningModelDocumentView: NSView {
    override var isFlipped: Bool { true }
}
