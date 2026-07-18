import AppKit

@MainActor
final class ComposerReasoningModelListView: NSView {
    private var groups: [ChatComposerActionRowView.ReasoningModelGroup]
    private var selectedProviderID: String
    private var selectedModelID: String
    private let onModelSelected: (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void
    private let onCancel: () -> Void
    private let scrollView = NSScrollView()
    private let documentView = ComposerReasoningModelDocumentView()
    private var structure: Structure
    private var arrangedViews: [NSView] = []
    private var rowsByIdentity: [String: ComposerReasoningMenuRowView] = [:]

    override var isFlipped: Bool { true }

    var focusableRows: [ComposerReasoningMenuRowView] {
        arrangedViews.compactMap { $0 as? ComposerReasoningMenuRowView }.filter(\.acceptsFirstResponder)
    }

    init(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        selectedProviderID: String,
        selectedModelID: String,
        onModelSelected: @escaping (ChatComposerActionRowView.ReasoningModelSelectionRequest) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.groups = groups
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        self.onModelSelected = onModelSelected
        self.onCancel = onCancel
        structure = Structure(groups: groups)
        super.init(frame: .zero)
        setup()
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        selectedProviderID: String,
        selectedModelID: String
    ) {
        let nextStructure = Structure(groups: groups)
        let structureChanged = structure != nextStructure
        self.groups = groups
        self.selectedProviderID = selectedProviderID
        self.selectedModelID = selectedModelID
        structure = nextStructure

        if structureChanged {
            rebuildRows()
            resetScrollPosition()
        } else {
            updateRowSelections()
        }
        needsLayout = true
    }

    func resetScrollPosition() {
        scrollView.contentView.scroll(to: .zero)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        layoutRows()
    }

    #if DEBUG
    var debugShowsProviderHeaders: Bool { structure.showsProviderHeaders }
    var debugScrollOrigin: NSPoint { scrollView.contentView.bounds.origin }
    var debugDocumentHeight: CGFloat { documentView.frame.height }
    var debugModelRowIdentities: [String] { structure.options.map(\.identity) }
    #endif

    private func setup() {
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        addSubview(scrollView)
    }

    private func rebuildRows() {
        arrangedViews.forEach { $0.removeFromSuperview() }
        arrangedViews = []
        rowsByIdentity = [:]

        let visibleGroups = structure.visibleGroups
        guard !visibleGroups.isEmpty else {
            let row = ComposerReasoningMenuRowView()
            row.configure(.init(
                title: "No models available",
                iconName: nil,
                trailingIconName: nil,
                accessibilityLabel: "No models available",
                isSelected: false,
                isEnabled: false,
                action: {},
                cancelAction: onCancel
            ))
            append(row)
            return
        }

        for (groupIndex, group) in visibleGroups.enumerated() {
            if structure.showsProviderHeaders {
                append(ComposerReasoningHeaderView(title: group.providerTitle ?? group.providerID.capitalized))
            }

            for option in group.options {
                let row = ComposerReasoningMenuRowView()
                configure(row: row, option: option)
                rowsByIdentity[option.identity] = row
                append(row)
            }

            if structure.showsProviderHeaders, groupIndex < visibleGroups.count - 1 {
                append(AppKitComposerPopoverDividerView())
            }
        }
    }

    private func updateRowSelections() {
        for option in structure.options {
            guard let row = rowsByIdentity[option.identity] else { continue }
            configure(row: row, option: option)
        }
    }

    private func configure(
        row: ComposerReasoningMenuRowView,
        option: ChatComposerActionRowView.ReasoningModelOption
    ) {
        let isSelected = option.providerID == selectedProviderID && option.value == selectedModelID
        row.configure(.init(
            title: option.title,
            iconName: nil,
            trailingIconName: isSelected ? "checkmark" : nil,
            accessibilityLabel: accessibilityLabel(for: option),
            isSelected: isSelected,
            isEnabled: true,
            showsFocusBackground: true,
            activatesWithRightArrow: false,
            action: { [weak self] in
                self?.onModelSelected(.init(providerID: option.providerID, modelID: option.value))
            },
            cancelAction: onCancel
        ))
    }

    private func accessibilityLabel(
        for option: ChatComposerActionRowView.ReasoningModelOption
    ) -> String {
        guard structure.showsProviderHeaders,
              let group = structure.visibleGroups.first(where: { $0.providerID == option.providerID }) else {
            return option.title
        }
        let trimmedTitle = group.providerTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let providerTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? group.providerID.capitalized
        return "\(providerTitle), \(option.title)"
    }

    private func append(_ view: NSView) {
        arrangedViews.append(view)
        documentView.addSubview(view)
    }

    private func layoutRows() {
        let contentHeight = ComposerReasoningMenuMetrics.modelDocumentHeight(groups: groups)
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(bounds.height, contentHeight)
        )

        var nextY = ComposerReasoningMenuMetrics.modelMenuTopInset(
            showsProviderHeaders: structure.showsProviderHeaders
        )
        for arrangedView in arrangedViews {
            let layout = layoutMetrics(for: arrangedView)
            arrangedView.frame = NSRect(
                x: layout.originX,
                y: nextY + layout.leadingSpacing,
                width: documentView.bounds.width - layout.horizontalInsets,
                height: layout.height
            )
            nextY += layout.leadingSpacing + layout.height + layout.trailingSpacing
        }
    }

    private func layoutMetrics(for view: NSView) -> LayoutMetrics {
        if view is ComposerReasoningHeaderView {
            return LayoutMetrics(
                originX: ComposerReasoningMenuMetrics.headerInset,
                horizontalInsets: ComposerReasoningMenuMetrics.headerInset * 2,
                height: ComposerReasoningMenuMetrics.headerHeight,
                leadingSpacing: 0,
                trailingSpacing: ComposerReasoningMenuMetrics.headerBottomSpacing
            )
        }
        if view is AppKitComposerPopoverDividerView {
            return LayoutMetrics(
                originX: AppKitComposerPopoverDividerView.horizontalInset,
                horizontalInsets: AppKitComposerPopoverDividerView.horizontalInset * 2,
                height: AppKitComposerPopoverDividerView.height,
                leadingSpacing: ComposerReasoningMenuMetrics.dividerSpacing,
                trailingSpacing: ComposerReasoningMenuMetrics.dividerSpacing
            )
        }
        return LayoutMetrics(
            originX: ComposerReasoningMenuMetrics.horizontalInset,
            horizontalInsets: ComposerReasoningMenuMetrics.horizontalInset * 2,
            height: ComposerReasoningMenuMetrics.rowHeight,
            leadingSpacing: 0,
            trailingSpacing: 0
        )
    }
}

private extension ComposerReasoningModelListView {
    struct Structure: Equatable {
        let visibleGroups: [ChatComposerActionRowView.ReasoningModelGroup]

        init(groups: [ChatComposerActionRowView.ReasoningModelGroup]) {
            visibleGroups = groups.filter { !$0.options.isEmpty }
        }

        var showsProviderHeaders: Bool { visibleGroups.count > 1 }
        var options: [ChatComposerActionRowView.ReasoningModelOption] { visibleGroups.flatMap(\.options) }
    }

    struct LayoutMetrics {
        let originX: CGFloat
        let horizontalInsets: CGFloat
        let height: CGFloat
        let leadingSpacing: CGFloat
        let trailingSpacing: CGFloat
    }
}

private final class ComposerReasoningModelDocumentView: NSView {
    override var isFlipped: Bool { true }
}
