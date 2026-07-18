@preconcurrency import AppKit

extension ChatComposerActionRowView {
    func toggleTaskWorkspaceMenu() {
        guard let workspace = configuration?.taskWorkspace,
              configuration?.areControlsDisabled == false else {
            closeTaskWorkspaceMenu()
            return
        }
        if let taskWorkspacePopover {
            if taskWorkspacePopover.isShown {
                closeTaskWorkspaceMenu()
                return
            }
            finishTaskWorkspaceMenuClose(for: taskWorkspacePopover)
        }

        let controller = ComposerTaskWorkspaceMenuViewController(
            configuration: workspace,
            onAddFolders: { [weak self] in
                guard let self else {
                    return
                }
                closeTaskWorkspaceMenu()
                configuration?.taskWorkspace?.onAddFolders([])
            },
            onRemoveGrant: { [weak self] path in
                guard let self else {
                    return
                }
                closeTaskWorkspaceMenu()
                configuration?.taskWorkspace?.onRemoveGrant(path)
            },
            onRequestClose: { [weak self] in
                self?.closeTaskWorkspaceMenu()
            }
        )
        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = false
        popover.delegate = self
        popover.contentViewController = controller
        taskWorkspaceMenuController = controller
        taskWorkspacePopover = popover
        popover.show(relativeTo: worktreeButton.bounds, of: worktreeButton, preferredEdge: .minY)
    }

    func closeTaskWorkspaceMenu() {
        guard let popover = taskWorkspacePopover else {
            worktreeButton.releaseMenuFocusIfNeeded()
            return
        }
        popover.performClose(nil)
        finishTaskWorkspaceMenuClose(for: popover)
    }

    func finishTaskWorkspaceMenuClose(for popover: NSPopover) {
        guard taskWorkspacePopover === popover else {
            return
        }
        popover.delegate = nil
        taskWorkspacePopover = nil
        taskWorkspaceMenuController = nil
        worktreeButton.releaseMenuFocusIfNeeded()
    }
}

@MainActor
final class ComposerTaskWorkspaceMenuViewController: NSViewController {
    private var configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration
    private let onAddFolders: () -> Void
    private let onRemoveGrant: (String) -> Void
    private let onRequestClose: () -> Void
    private var menuView: ComposerTaskWorkspaceMenuView?

    init(
        configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration,
        onAddFolders: @escaping () -> Void,
        onRemoveGrant: @escaping (String) -> Void,
        onRequestClose: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onAddFolders = onAddFolders
        self.onRemoveGrant = onRemoveGrant
        self.onRequestClose = onRequestClose
        super.init(nibName: nil, bundle: nil)
        preferredContentSize = ComposerTaskWorkspaceMenuMetrics.contentSize(
            grantCount: configuration.grantedRoots.count
        )
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let menuView = ComposerTaskWorkspaceMenuView(
            configuration: configuration,
            onAddFolders: onAddFolders,
            onRemoveGrant: onRemoveGrant,
            onCancel: onRequestClose
        )
        self.menuView = menuView
        view = menuView
    }

    func update(configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration) {
        self.configuration = configuration
        let size = ComposerTaskWorkspaceMenuMetrics.contentSize(
            grantCount: configuration.grantedRoots.count
        )
        preferredContentSize = size
        menuView?.update(configuration: configuration)
    }
}

@MainActor
private final class ComposerTaskWorkspaceMenuView: AppKitComposerPopoverSurfaceView {
    private var configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration
    private let onAddFolders: () -> Void
    private let onRemoveGrant: (String) -> Void
    private let onCancel: () -> Void
    private let scrollView = NSScrollView()
    private let documentView = ComposerTaskWorkspaceDocumentView()
    private let headerField = ComposerReasoningHeaderView(title: "Workspace")
    private let primaryDivider = AppKitComposerPopoverDividerView()
    private let grantsDivider = AppKitComposerPopoverDividerView()
    private var rows: [ComposerReasoningMenuRowView] = []

    init(
        configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration,
        onAddFolders: @escaping () -> Void,
        onRemoveGrant: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.configuration = configuration
        self.onAddFolders = onAddFolders
        self.onRemoveGrant = onRemoveGrant
        self.onCancel = onCancel
        super.init(frame: NSRect(
            origin: .zero,
            size: ComposerTaskWorkspaceMenuMetrics.contentSize(grantCount: configuration.grantedRoots.count)
        ))
        setup()
        rebuildRows()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration) {
        self.configuration = configuration
        frame.size = ComposerTaskWorkspaceMenuMetrics.contentSize(
            grantCount: configuration.grantedRoots.count
        )
        rebuildRows()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        scrollView.frame = bounds
        documentView.frame = NSRect(
            x: 0,
            y: 0,
            width: bounds.width,
            height: max(
                bounds.height,
                ComposerTaskWorkspaceMenuMetrics.documentHeight(grantCount: configuration.grantedRoots.count)
            )
        )
        var nextY = ComposerTaskWorkspaceMenuMetrics.verticalInset
        headerField.frame = NSRect(
            x: ComposerTaskWorkspaceMenuMetrics.headerInset,
            y: nextY,
            width: documentView.bounds.width - ComposerTaskWorkspaceMenuMetrics.headerInset * 2,
            height: ComposerTaskWorkspaceMenuMetrics.headerHeight
        )
        nextY += ComposerTaskWorkspaceMenuMetrics.headerHeight + ComposerTaskWorkspaceMenuMetrics.headerBottomSpacing

        for (index, row) in rows.enumerated() {
            row.frame = NSRect(
                x: ComposerTaskWorkspaceMenuMetrics.horizontalInset,
                y: nextY,
                width: documentView.bounds.width - ComposerTaskWorkspaceMenuMetrics.horizontalInset * 2,
                height: ComposerTaskWorkspaceMenuMetrics.rowHeight
            )
            nextY += ComposerTaskWorkspaceMenuMetrics.rowHeight

            if index == 0 {
                nextY = layoutDivider(primaryDivider, from: nextY)
            } else if index == 1, !configuration.grantedRoots.isEmpty {
                nextY = layoutDivider(grantsDivider, from: nextY)
            }
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
        scrollView.drawsBackground = false
        scrollView.contentView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.documentView = documentView
        addSubview(scrollView)
        headerField.setAccessibilityElement(false)
        documentView.addSubview(headerField)
        documentView.addSubview(primaryDivider)
        documentView.addSubview(grantsDivider)
    }

    private func rebuildRows() {
        rows.forEach { $0.removeFromSuperview() }
        rows = [makePrimaryRow(), makeAddFoldersRow()] + configuration.grantedRoots.map(makeGrantRemovalRow)
        for row in rows {
            documentView.addSubview(row)
        }
        grantsDivider.isHidden = configuration.grantedRoots.isEmpty
    }

    private func makePrimaryRow() -> ComposerReasoningMenuRowView {
        let strategy = configuration.ownershipStrategy
        let workspaceName = URL(fileURLWithPath: configuration.primaryRoot, isDirectory: true).lastPathComponent
        let row = ComposerReasoningMenuRowView()
        row.toolTip = configuration.primaryRoot
        row.configure(.init(
            title: ComposerTaskWorkspacePresentation.workspaceKindName(strategy),
            subtitle: workspaceName,
            iconName: "folder",
            trailingIconName: nil,
            accessibilityLabel: "\(ComposerTaskWorkspacePresentation.workspaceKindName(strategy)): \(workspaceName)",
            isSelected: false,
            isEnabled: false,
            action: {},
            cancelAction: onCancel
        ))
        return row
    }

    private func makeAddFoldersRow() -> ComposerReasoningMenuRowView {
        let row = ComposerReasoningMenuRowView()
        row.toolTip = configuration.canEdit ? nil : configuration.disabledTooltip
        row.configure(.init(
            title: "Add Folder Access...",
            iconName: "folder.badge.plus",
            trailingIconName: nil,
            accessibilityLabel: "Add folder access",
            isSelected: false,
            isEnabled: configuration.canEdit,
            action: onAddFolders,
            cancelAction: onCancel
        ))
        return row
    }

    private func makeGrantRemovalRow(_ path: String) -> ComposerReasoningMenuRowView {
        let row = ComposerReasoningMenuRowView()
        row.toolTip = configuration.canEdit ? path : configuration.disabledTooltip
        row.configure(.init(
            title: ComposerTaskWorkspacePresentation.grantDisplayPath(path),
            subtitle: "Click to remove",
            iconName: "folder.badge.minus",
            trailingIconName: nil,
            accessibilityLabel: ComposerTaskWorkspacePresentation.grantRemovalAccessibilityLabel(path),
            isSelected: false,
            isEnabled: configuration.canEdit,
            action: { [onRemoveGrant] in onRemoveGrant(path) },
            cancelAction: onCancel
        ))
        return row
    }

    private func layoutDivider(_ divider: NSView, from nextY: CGFloat) -> CGFloat {
        divider.frame = NSRect(
            x: AppKitComposerPopoverDividerView.horizontalInset,
            y: nextY + ComposerTaskWorkspaceMenuMetrics.dividerSpacing,
            width: documentView.bounds.width - AppKitComposerPopoverDividerView.horizontalInset * 2,
            height: AppKitComposerPopoverDividerView.height
        )
        return divider.frame.maxY + ComposerTaskWorkspaceMenuMetrics.dividerSpacing
    }
}

enum ComposerTaskWorkspaceMenuMetrics {
    static let width: CGFloat = 360
    static let maxHeight: CGFloat = 360
    static let horizontalInset: CGFloat = ComposerReasoningMenuMetrics.horizontalInset
    static let verticalInset: CGFloat = ComposerPermissionMenuMetrics.verticalInset
    static let headerInset: CGFloat = ComposerReasoningMenuMetrics.headerInset
    static let headerHeight: CGFloat = ComposerReasoningMenuMetrics.headerHeight
    static let headerBottomSpacing: CGFloat = ComposerReasoningMenuMetrics.headerBottomSpacing
    static let rowHeight: CGFloat = ComposerReasoningMenuMetrics.permissionRowHeight
    static let dividerSpacing: CGFloat = ComposerReasoningMenuMetrics.dividerSpacing

    @MainActor
    static func contentSize(grantCount: Int) -> NSSize {
        NSSize(
            width: width,
            height: min(maxHeight, documentHeight(grantCount: grantCount))
        )
    }

    @MainActor
    static func documentHeight(grantCount: Int) -> CGFloat {
        let rowCount = 2 + grantCount
        let dividerCount = grantCount == 0 ? 1 : 2
        return verticalInset * 2 +
            headerHeight +
            headerBottomSpacing +
            rowHeight * CGFloat(rowCount) +
            (AppKitComposerPopoverDividerView.height + dividerSpacing * 2) * CGFloat(dividerCount)
    }
}

private final class ComposerTaskWorkspaceDocumentView: NSView {
    override var isFlipped: Bool { true }
}
