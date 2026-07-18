import AppKit

@MainActor
final class ComposerWorktreeMenuViewController: NSViewController {
    private var options: [ChatComposerActionRowView.WorktreeLocationOptionPresentation]
    private var selectedValue: String
    private let onUseWorktreeSelected: (Bool) -> Void
    private let onRequestCloseMainMenu: () -> Void
    private var menuView: ComposerWorktreeMenuView?

    init(
        options: [ChatComposerActionRowView.WorktreeLocationOptionPresentation],
        selectedValue: String,
        onUseWorktreeSelected: @escaping (Bool) -> Void,
        onRequestCloseMainMenu: @escaping () -> Void
    ) {
        self.options = options
        self.selectedValue = selectedValue
        self.onUseWorktreeSelected = onUseWorktreeSelected
        self.onRequestCloseMainMenu = onRequestCloseMainMenu
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerWorktreeMenuMetrics.contentSize(optionCount: options.count)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let menuView = ComposerWorktreeMenuView(
            options: options,
            selectedValue: selectedValue,
            onUseWorktreeSelected: { [weak self] value in
                self?.selectUseWorktree(value)
            },
            onCancel: { [weak self] in
                self?.onRequestCloseMainMenu()
            }
        )
        self.menuView = menuView
        view = menuView
    }

    func update(
        options: [ChatComposerActionRowView.WorktreeLocationOptionPresentation],
        selectedValue: String
    ) {
        self.options = options
        self.selectedValue = selectedValue
        let size = ComposerWorktreeMenuMetrics.contentSize(optionCount: options.count)
        preferredContentSize = size
        menuView?.update(options: options, selectedValue: selectedValue)
    }

    private func selectUseWorktree(_ value: Bool) {
        onUseWorktreeSelected(value)
        onRequestCloseMainMenu()
    }
}

@MainActor
private final class ComposerWorktreeMenuView: AppKitComposerPopoverSurfaceView {
    private var options: [ChatComposerActionRowView.WorktreeLocationOptionPresentation]
    private var selectedValue: String
    private let onUseWorktreeSelected: (Bool) -> Void
    private let onCancel: () -> Void
    private let headerField = ComposerReasoningHeaderView(title: "Thread location")
    private var rows: [ComposerReasoningMenuRowView] = []

    init(
        options: [ChatComposerActionRowView.WorktreeLocationOptionPresentation],
        selectedValue: String,
        onUseWorktreeSelected: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.options = options
        self.selectedValue = selectedValue
        self.onUseWorktreeSelected = onUseWorktreeSelected
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: ComposerWorktreeMenuMetrics.contentSize(optionCount: options.count)))
        setup()
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        options: [ChatComposerActionRowView.WorktreeLocationOptionPresentation],
        selectedValue: String
    ) {
        self.options = options
        self.selectedValue = selectedValue
        frame.size = ComposerWorktreeMenuMetrics.contentSize(optionCount: options.count)
        rebuildRows()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var nextY = ComposerWorktreeMenuMetrics.verticalInset
        headerField.frame = NSRect(
            x: ComposerWorktreeMenuMetrics.headerInset,
            y: nextY,
            width: bounds.width - ComposerWorktreeMenuMetrics.headerInset * 2,
            height: ComposerWorktreeMenuMetrics.headerHeight
        )
        nextY += ComposerWorktreeMenuMetrics.headerHeight + ComposerWorktreeMenuMetrics.headerBottomSpacing

        for row in rows {
            row.frame = NSRect(
                x: ComposerWorktreeMenuMetrics.horizontalInset,
                y: nextY,
                width: bounds.width - ComposerWorktreeMenuMetrics.horizontalInset * 2,
                height: ComposerWorktreeMenuMetrics.rowHeight
            )
            nextY += ComposerWorktreeMenuMetrics.rowHeight
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
        headerField.setAccessibilityElement(false)
        addSubview(headerField)
    }

    private func rebuildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows = options.map { option in
            let row = ComposerReasoningMenuRowView()
            let isSelected = option.value == selectedValue
            row.configure(.init(
                title: option.title,
                subtitle: nil,
                iconName: option.symbolName,
                iconRotationRadians: option.iconRotationRadians,
                trailingIconName: isSelected ? "checkmark" : nil,
                accessibilityLabel: option.title,
                isSelected: isSelected,
                isEnabled: true,
                action: { [weak self] in self?.onUseWorktreeSelected(option.usesWorktree) },
                cancelAction: { [weak self] in self?.onCancel() }
            ))
            addSubview(row)
            return row
        }
    }
}

enum ComposerWorktreeMenuMetrics {
    static let width: CGFloat = 280
    static let horizontalInset: CGFloat = ComposerPermissionMenuMetrics.horizontalInset
    static let verticalInset: CGFloat = ComposerPermissionMenuMetrics.verticalInset
    static let headerInset: CGFloat = ComposerPermissionMenuMetrics.headerInset
    static let headerHeight: CGFloat = ComposerPermissionMenuMetrics.headerHeight
    static let headerBottomSpacing: CGFloat = ComposerPermissionMenuMetrics.headerBottomSpacing
    static let rowHeight: CGFloat = ComposerReasoningMenuMetrics.rowHeight

    @MainActor
    static func contentSize(optionCount: Int) -> NSSize {
        NSSize(
            width: width,
            height: verticalInset * 2 +
                headerHeight +
                headerBottomSpacing +
                rowHeight * CGFloat(optionCount)
        )
    }
}
