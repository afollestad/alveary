import AppKit

@MainActor
final class ComposerPermissionMenuViewController: NSViewController {
    private var options: [ChatComposerActionRowView.PermissionOptionPresentation]
    private var selectedValue: String
    private let onPermissionSelected: (String) -> Void
    private let onRequestCloseMainMenu: () -> Void
    private var menuView: ComposerPermissionMenuView?

    init(
        options: [ChatComposerActionRowView.PermissionOptionPresentation],
        selectedValue: String,
        onPermissionSelected: @escaping (String) -> Void,
        onRequestCloseMainMenu: @escaping () -> Void
    ) {
        self.options = options
        self.selectedValue = selectedValue
        self.onPermissionSelected = onPermissionSelected
        self.onRequestCloseMainMenu = onRequestCloseMainMenu
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerPermissionMenuMetrics.contentSize(optionCount: options.count)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let menuView = ComposerPermissionMenuView(
            options: options,
            selectedValue: selectedValue,
            onPermissionSelected: { [weak self] value in
                self?.selectPermission(value)
            },
            onCancel: { [weak self] in
                self?.onRequestCloseMainMenu()
            }
        )
        self.menuView = menuView
        view = menuView
    }

    func update(
        options: [ChatComposerActionRowView.PermissionOptionPresentation],
        selectedValue: String
    ) {
        self.options = options
        self.selectedValue = selectedValue
        let size = ComposerPermissionMenuMetrics.contentSize(optionCount: options.count)
        preferredContentSize = size
        menuView?.update(options: options, selectedValue: selectedValue)
    }

    private func selectPermission(_ value: String) {
        onPermissionSelected(value)
        onRequestCloseMainMenu()
    }
}

@MainActor
private final class ComposerPermissionMenuView: AppKitComposerPopoverSurfaceView {
    private var options: [ChatComposerActionRowView.PermissionOptionPresentation]
    private var selectedValue: String
    private let onPermissionSelected: (String) -> Void
    private let onCancel: () -> Void
    private let headerField = ComposerReasoningHeaderView(title: "Permission mode")
    private var rows: [ComposerReasoningMenuRowView] = []

    init(
        options: [ChatComposerActionRowView.PermissionOptionPresentation],
        selectedValue: String,
        onPermissionSelected: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.options = options
        self.selectedValue = selectedValue
        self.onPermissionSelected = onPermissionSelected
        self.onCancel = onCancel
        super.init(frame: NSRect(origin: .zero, size: ComposerPermissionMenuMetrics.contentSize(optionCount: options.count)))
        setup()
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(
        options: [ChatComposerActionRowView.PermissionOptionPresentation],
        selectedValue: String
    ) {
        self.options = options
        self.selectedValue = selectedValue
        frame.size = ComposerPermissionMenuMetrics.contentSize(optionCount: options.count)
        rebuildRows()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        var nextY = ComposerPermissionMenuMetrics.verticalInset
        headerField.frame = NSRect(
            x: ComposerPermissionMenuMetrics.headerInset,
            y: nextY,
            width: bounds.width - ComposerPermissionMenuMetrics.headerInset * 2,
            height: ComposerPermissionMenuMetrics.headerHeight
        )
        nextY += ComposerPermissionMenuMetrics.headerHeight + ComposerPermissionMenuMetrics.headerBottomSpacing

        for row in rows {
            row.frame = NSRect(
                x: ComposerPermissionMenuMetrics.horizontalInset,
                y: nextY,
                width: bounds.width - ComposerPermissionMenuMetrics.horizontalInset * 2,
                height: ComposerPermissionMenuMetrics.rowHeight
            )
            nextY += ComposerPermissionMenuMetrics.rowHeight
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
                subtitle: option.description,
                iconName: option.symbolName,
                trailingIconName: isSelected ? "checkmark" : nil,
                accessibilityLabel: option.title,
                isSelected: isSelected,
                isEnabled: true,
                isWarning: option.isWarning,
                action: { [weak self] in self?.onPermissionSelected(option.value) },
                cancelAction: { [weak self] in self?.onCancel() }
            ))
            addSubview(row)
            return row
        }
    }
}

enum ComposerPermissionMenuMetrics {
    static let width: CGFloat = 480
    static let horizontalInset: CGFloat = ComposerReasoningMenuMetrics.horizontalInset
    static let verticalInset: CGFloat = 8
    static let headerInset: CGFloat = ComposerReasoningMenuMetrics.headerInset
    static let headerHeight: CGFloat = ComposerReasoningMenuMetrics.headerHeight
    static let headerBottomSpacing: CGFloat = ComposerReasoningMenuMetrics.headerBottomSpacing
    static let rowHeight: CGFloat = ComposerReasoningMenuMetrics.permissionRowHeight

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
