import AppKit

@MainActor
final class ComposerReasoningModelListView: NSView {
    private var groups: [ReasoningModelGroup]
    private var inheritOption: ReasoningInheritOption?
    private var selectedHarnessID: String
    private var selectedModelID: String
    private let onModelSelected: (ReasoningModelSelectionRequest) -> Void
    private let onInheritSelected: () -> Void
    private let onCancel: () -> Void
    private let scrollView = NSScrollView()
    private let documentView = ComposerReasoningModelDocumentView()
    private var structure: Structure
    private var arrangedViews: [NSView] = []
    private var rowsByIdentity: [String: ComposerReasoningMenuRowView] = [:]
    /// Kept apart from `rowsByIdentity` so no `harness:model` identity can collide with it.
    private var inheritRow: ComposerReasoningMenuRowView?

    override var isFlipped: Bool { true }

    var focusableRows: [ComposerReasoningMenuRowView] {
        arrangedViews.compactMap { $0 as? ComposerReasoningMenuRowView }.filter(\.acceptsFirstResponder)
    }

    /// Where keyboard focus should land when the list is revealed programmatically, so arrow keys
    /// start from the current model rather than the top of the list.
    var preferredFocusRow: ComposerReasoningMenuRowView? {
        if inheritOption?.isSelected == true, let inheritRow, inheritRow.acceptsFirstResponder {
            return inheritRow
        }
        let selectedIdentity = "\(selectedHarnessID):\(selectedModelID)"
        if let selectedRow = rowsByIdentity[selectedIdentity], selectedRow.acceptsFirstResponder {
            return selectedRow
        }
        return focusableRows.first
    }

    init(
        groups: [ReasoningModelGroup],
        inheritOption: ReasoningInheritOption? = nil,
        selectedHarnessID: String,
        selectedModelID: String,
        onModelSelected: @escaping (ReasoningModelSelectionRequest) -> Void,
        onInheritSelected: @escaping () -> Void = {},
        onCancel: @escaping () -> Void
    ) {
        self.groups = groups
        self.inheritOption = inheritOption
        self.selectedHarnessID = selectedHarnessID
        self.selectedModelID = selectedModelID
        self.onModelSelected = onModelSelected
        self.onInheritSelected = onInheritSelected
        self.onCancel = onCancel
        structure = Structure(groups: groups, showsInheritRow: inheritOption != nil)
        super.init(frame: .zero)
        setup()
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        nil
    }

    func update(
        groups: [ReasoningModelGroup],
        inheritOption: ReasoningInheritOption? = nil,
        selectedHarnessID: String,
        selectedModelID: String
    ) {
        let nextStructure = Structure(groups: groups, showsInheritRow: inheritOption != nil)
        let structureChanged = structure != nextStructure
        self.groups = groups
        self.inheritOption = inheritOption
        self.selectedHarnessID = selectedHarnessID
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
    var debugShowsHarnessHeaders: Bool { structure.showsHarnessHeaders }
    var debugScrollOrigin: NSPoint { scrollView.contentView.bounds.origin }
    var debugDocumentHeight: CGFloat { documentView.frame.height }
    var debugModelRowIdentities: [String] { structure.options.map(\.identity) }
    var debugInheritRow: ComposerReasoningMenuRowView? { inheritRow }
    var debugArrangedViews: [NSView] { arrangedViews }
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
        inheritRow = nil

        if let inheritOption {
            let row = ComposerReasoningMenuRowView()
            configure(inheritRow: row, option: inheritOption)
            inheritRow = row
            append(row)
            append(AppKitComposerPopoverDividerView())
        }

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
            if structure.showsHarnessHeaders {
                append(ComposerReasoningHeaderView(title: group.harnessTitle ?? group.harnessID.capitalized))
            }

            for option in group.options {
                let row = ComposerReasoningMenuRowView()
                configure(row: row, option: option)
                rowsByIdentity[option.identity] = row
                append(row)
            }

            if structure.showsHarnessHeaders, groupIndex < visibleGroups.count - 1 {
                append(AppKitComposerPopoverDividerView())
            }
        }
    }

    private func updateRowSelections() {
        if let inheritRow, let inheritOption {
            configure(inheritRow: inheritRow, option: inheritOption)
        }
        for option in structure.options {
            guard let row = rowsByIdentity[option.identity] else { continue }
            configure(row: row, option: option)
        }
    }

    private func configure(
        row: ComposerReasoningMenuRowView,
        option: ReasoningModelOption
    ) {
        let isSelected = inheritOption?.isSelected != true &&
            option.harnessID == selectedHarnessID && option.value == selectedModelID
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
                self?.onModelSelected(.init(harnessID: option.harnessID, modelID: option.value))
            },
            cancelAction: onCancel
        ))
    }

    private func configure(inheritRow row: ComposerReasoningMenuRowView, option: ReasoningInheritOption) {
        row.configure(.init(
            title: option.title,
            subtitle: option.detail,
            iconName: nil,
            trailingIconName: option.isSelected ? "checkmark" : nil,
            accessibilityLabel: "\(option.title), \(option.detail)",
            isSelected: option.isSelected,
            isEnabled: option.isEnabled,
            showsFocusBackground: true,
            activatesWithRightArrow: false,
            action: { [weak self] in
                self?.onInheritSelected()
            },
            cancelAction: onCancel
        ))
    }

    private func accessibilityLabel(
        for option: ReasoningModelOption
    ) -> String {
        guard structure.showsHarnessHeaders,
              let group = structure.visibleGroups.first(where: { $0.harnessID == option.harnessID }) else {
            return option.title
        }
        let trimmedTitle = group.harnessTitle?.trimmingCharacters(in: .whitespacesAndNewlines)
        let harnessTitle = trimmedTitle.flatMap { $0.isEmpty ? nil : $0 } ?? group.harnessID.capitalized
        return "\(harnessTitle), \(option.title)"
    }

    private func append(_ view: NSView) {
        arrangedViews.append(view)
        documentView.addSubview(view)
    }

    private func layoutRows() {
        let contentHeight = ComposerReasoningMenuMetrics.modelDocumentHeight(
            groups: groups,
            showsInheritRow: structure.showsInheritRow
        )
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(bounds.height, contentHeight)
        )

        var nextY = ComposerReasoningMenuMetrics.modelMenuTopInset(
            showsHarnessHeaders: structure.showsHarnessHeaders,
            showsInheritRow: structure.showsInheritRow
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
            height: view === inheritRow ? ComposerReasoningMenuMetrics.subtitledRowHeight : ComposerReasoningMenuMetrics.rowHeight,
            leadingSpacing: 0,
            trailingSpacing: 0
        )
    }
}

private extension ComposerReasoningModelListView {
    struct Structure: Equatable {
        let visibleGroups: [ReasoningModelGroup]
        let showsInheritRow: Bool

        init(groups: [ReasoningModelGroup], showsInheritRow: Bool) {
            visibleGroups = groups.filter { !$0.options.isEmpty }
            self.showsInheritRow = showsInheritRow
        }

        var showsHarnessHeaders: Bool { visibleGroups.count > 1 }
        var options: [ReasoningModelOption] { visibleGroups.flatMap(\.options) }
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
