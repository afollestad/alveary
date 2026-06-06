@preconcurrency import AppKit

private typealias Metrics = AppKitComposerOverlayMetrics

@MainActor
final class AppKitComposerOverlayPanelView: NSView {
    struct Configuration {
        let title: String
        let rows: [AppKitComposerOverlayOptionRowView.Configuration]
        let density: AppKitComposerOverlayPanelDensity
        let titleFont: NSFont
        let pageText: String?
        let canNavigateBackward: Bool
        let canNavigateForward: Bool
        let dismissTitle: String
        let primaryTitle: String
        let primarySymbolName: String?
        let isPrimaryEnabled: Bool
        let isResolving: Bool
        let onNavigateBackward: () -> Void
        let onNavigateForward: () -> Void
        let onDismiss: () -> Void
        let onPrimary: () -> Void

        init(
            title: String,
            rows: [AppKitComposerOverlayOptionRowView.Configuration],
            density: AppKitComposerOverlayPanelDensity = Metrics.regularDensity,
            titleFont: NSFont = .systemFont(ofSize: 15, weight: .semibold),
            pageText: String? = nil,
            canNavigateBackward: Bool = false,
            canNavigateForward: Bool = false,
            dismissTitle: String = "Dismiss",
            primaryTitle: String,
            primarySymbolName: String? = nil,
            isPrimaryEnabled: Bool = true,
            isResolving: Bool = false,
            onNavigateBackward: @escaping () -> Void = {},
            onNavigateForward: @escaping () -> Void = {},
            onDismiss: @escaping () -> Void,
            onPrimary: @escaping () -> Void
        ) {
            self.title = title
            self.rows = rows
            self.density = density
            self.titleFont = titleFont
            self.pageText = pageText
            self.canNavigateBackward = canNavigateBackward
            self.canNavigateForward = canNavigateForward
            self.dismissTitle = dismissTitle
            self.primaryTitle = primaryTitle
            self.primarySymbolName = primarySymbolName
            self.isPrimaryEnabled = isPrimaryEnabled
            self.isResolving = isResolving
            self.onNavigateBackward = onNavigateBackward
            self.onNavigateForward = onNavigateForward
            self.onDismiss = onDismiss
            self.onPrimary = onPrimary
        }
    }

    var onPreferredSizeInvalidated: (() -> Void)?

    private let backgroundView = AppKitFlippedDynamicColorView()
    private let titleField = NSTextField(labelWithString: "")
    let previousButton = AppKitComposerOverlayNavigationButton()
    let nextButton = AppKitComposerOverlayNavigationButton()
    private let pageField = NSTextField(labelWithString: "")
    let dismissButton = AppKitTranscriptApprovalButton()
    let primaryButton = AppKitTranscriptApprovalButton()
    var rowViews: [AppKitComposerOverlayOptionRowView] = []
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(width: bounds.width))
    }

    func configure(_ configuration: Configuration?) {
        self.configuration = configuration
        guard let configuration else {
            rowViews.forEach { $0.removeFromSuperview() }
            rowViews = []
            return
        }

        titleField.stringValue = configuration.title
        titleField.font = configuration.titleFont
        previousButton.isHidden = configuration.pageText == nil
        previousButton.isEnabled = configuration.canNavigateBackward && !configuration.isResolving
        nextButton.isHidden = configuration.pageText == nil
        nextButton.isEnabled = configuration.canNavigateForward && !configuration.isResolving
        pageField.stringValue = configuration.pageText ?? ""
        pageField.isHidden = configuration.pageText == nil
        dismissButton.title = configuration.dismissTitle
        dismissButton.shortcutTitle = "Esc"
        dismissButton.isEnabled = !configuration.isResolving
        primaryButton.title = configuration.isResolving ? "Working..." : configuration.primaryTitle
        primaryButton.symbolName = configuration.primarySymbolName
        primaryButton.shortcutTitle = configuration.primarySymbolName == nil ? "↩" : nil
        primaryButton.isEnabled = configuration.isPrimaryEnabled && !configuration.isResolving

        rebuildRows(configuration.rows)
        updateKeyViewLoop()
        invalidateIntrinsicContentSize()
        needsLayout = true
        invalidatePreferredSize(force: true)
    }

    func measuredHeight(width: CGFloat) -> CGFloat {
        guard let configuration else {
            return 0
        }
        let density = configuration.density
        let contentWidth = max(width - (density.panelPadding * 2), 0)
        let rowHeight = rowViews.enumerated().reduce(CGFloat.zero) { partialResult, item in
            let rowWidth = measuredRowWidth(at: item.offset, contentWidth: contentWidth)
            item.element.frame.size.width = rowWidth
            return partialResult + item.element.measuredHeight(width: rowWidth)
        }
        let rowsSpacing = rowViews.isEmpty ? 0 : CGFloat(rowViews.count - 1) * density.rowSpacing
        let footerHeight = density.placesFooterInlineWithLastRow && !rowViews.isEmpty
            ? 0
            : density.footerSpacing + Metrics.buttonHeight
        return ceil(
            density.topPadding
                + Metrics.headerHeight
                + density.headerRowsSpacing
                + rowHeight
                + rowsSpacing
                + footerHeight
                + density.panelPadding
        )
    }

    func focusInitialOption() {
        guard let focused = rowViews.first(where: \.configurationIsFocused) ?? rowViews.first else {
            window?.makeFirstResponder(self)
            return
        }
        focused.focusPreferredTarget()
    }

    @discardableResult
    // swiftlint:disable:next cyclomatic_complexity
    func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let configuration else {
            return false
        }
        switch event.specialKey {
        case .leftArrow:
            if configuration.canNavigateBackward {
                configuration.onNavigateBackward()
            }
            return true
        case .rightArrow:
            if configuration.canNavigateForward {
                configuration.onNavigateForward()
            }
            return true
        case .upArrow:
            focusAdjacentRow(delta: -1)
            return true
        case .downArrow:
            focusAdjacentRow(delta: 1)
            return true
        case .carriageReturn:
            if let row = focusedOrConfiguredRow,
               shouldReturnSelectFocusedRow(row) {
                row.performSubmitSelection()
                return true
            }
            guard configuration.isPrimaryEnabled, !configuration.isResolving else {
                return true
            }
            configuration.onPrimary()
            return true
        default:
            break
        }
        if event.keyCode == 48 {
            focusAdjacentKeyView(delta: event.modifierFlags.contains(.shift) ? -1 : 1)
            return true
        }
        if event.keyCode == 53 {
            configuration.onDismiss()
            return true
        }
        if event.charactersIgnoringModifiers == " " {
            if let row = focusedOrConfiguredRow {
                row.performSelectionFromKeyboard()
                return true
            }
        }
        return false
    }

    override func layout() {
        super.layout()
        layoutContent()
        invalidatePreferredSize(force: false)
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, bounds.contains(point) else {
            return nil
        }
        if !previousButton.isHidden,
           previousButton.frame.contains(point) {
            return previousButton.isEnabled ? previousButton : self
        }
        if !nextButton.isHidden,
           nextButton.frame.contains(point) {
            return nextButton.isEnabled ? nextButton : self
        }
        return super.hitTest(point)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateAppearance()
    }

    private func setup() {
        wantsLayer = true
        backgroundView.wantsLayer = true
        backgroundView.layer?.cornerRadius = Metrics.cornerRadius
        backgroundView.layer?.borderWidth = 1
        addSubview(backgroundView)

        titleField.font = .systemFont(ofSize: 17, weight: .semibold)
        titleField.textColor = .labelColor
        titleField.lineBreakMode = .byWordWrapping
        titleField.maximumNumberOfLines = 0
        backgroundView.addSubview(titleField)

        configureNavigationButton(previousButton, symbolName: "chevron.left", action: #selector(handlePrevious))
        configureNavigationButton(nextButton, symbolName: "chevron.right", action: #selector(handleNext))
        pageField.font = .systemFont(ofSize: 13, weight: .medium)
        pageField.textColor = .secondaryLabelColor
        pageField.alignment = .center
        [previousButton, pageField, nextButton].forEach { backgroundView.addSubview($0) }

        dismissButton.actionStyle = .secondary
        dismissButton.keyEventHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        dismissButton.target = self
        dismissButton.action = #selector(handleDismiss)
        primaryButton.actionStyle = .primary
        primaryButton.keyEventHandler = { [weak self] event in
            self?.handleKeyDown(event) ?? false
        }
        primaryButton.target = self
        primaryButton.action = #selector(handlePrimary)
        backgroundView.addSubview(dismissButton)
        backgroundView.addSubview(primaryButton)
        updateAppearance()
    }

    private func rebuildRows(_ rowConfigurations: [AppKitComposerOverlayOptionRowView.Configuration]) {
        let oldRowsByID = Dictionary(uniqueKeysWithValues: rowViews.map { ($0.configurationID, $0) })
        var reusedRows = Set<ObjectIdentifier>()
        let nextRows = rowConfigurations.map { rowConfiguration in
            let row = oldRowsByID[rowConfiguration.id] ?? AppKitComposerOverlayOptionRowView()
            reusedRows.insert(ObjectIdentifier(row))
            row.onPreferredSizeInvalidated = { [weak self] in
                self?.updateKeyViewLoop()
                self?.invalidatePreferredSize(force: true)
            }
            row.onKeyEvent = { [weak self] event in
                self?.handleKeyDown(event) ?? false
            }
            row.onCustomSubmit = { [weak self] in
                self?.handlePrimary()
            }
            row.onCustomCancel = { [weak self] in
                self?.handleDismiss()
            }
            row.onCustomMoveUp = { [weak self] in
                self?.focusAdjacentRow(delta: -1)
            }
            row.onCustomMoveDown = { [weak self] in
                self?.focusAdjacentRow(delta: 1)
            }
            row.onCustomMoveLeft = { [weak self] in
                guard let configuration = self?.configuration,
                      configuration.canNavigateBackward else {
                    return
                }
                configuration.onNavigateBackward()
            }
            row.onCustomMoveRight = { [weak self] in
                guard let configuration = self?.configuration,
                      configuration.canNavigateForward else {
                    return
                }
                configuration.onNavigateForward()
            }
            row.configure(rowConfiguration)
            if row.superview !== backgroundView {
                backgroundView.addSubview(row)
            }
            return row
        }
        rowViews
            .filter { !reusedRows.contains(ObjectIdentifier($0)) }
            .forEach { $0.removeFromSuperview() }
        rowViews = nextRows
    }

    private func updateKeyViewLoop() {
        let keyViews = focusableKeyViews
        for (index, view) in keyViews.enumerated() {
            view.nextKeyView = keyViews.indices.contains(index + 1) ? keyViews[index + 1] : keyViews.first
        }
        nextKeyView = keyViews.first
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }

        backgroundView.frame = bounds
        let density = configuration.density
        let contentWidth = max(bounds.width - (density.panelPadding * 2), 0)
        let titleWidth = max(contentWidth - navigationWidth, 0)
        titleField.frame = wrappedFrame(
            for: titleField,
            originX: density.panelPadding,
            originY: density.topPadding,
            width: titleWidth
        )

        layoutNavigation(contentWidth: contentWidth)

        var currentY = density.topPadding + Metrics.headerHeight + density.headerRowsSpacing
        var lastRowFrame = NSRect.zero
        for (index, row) in rowViews.enumerated() {
            let rowWidth = measuredRowWidth(at: index, contentWidth: contentWidth)
            let height = row.measuredHeight(width: rowWidth)
            row.frame = NSRect(x: density.panelPadding, y: currentY, width: rowWidth, height: height)
            lastRowFrame = row.frame
            currentY += height + density.rowSpacing
        }
        if !rowViews.isEmpty {
            currentY -= density.rowSpacing
        }

        let primarySize = primaryButton.fittingSize
        let footerY: CGFloat
        if density.placesFooterInlineWithLastRow, !rowViews.isEmpty {
            footerY = lastRowFrame.minY + floor((lastRowFrame.height - Metrics.buttonHeight) / 2)
        } else {
            currentY += density.footerSpacing
            footerY = currentY
        }
        primaryButton.frame = NSRect(
            x: bounds.width - density.panelPadding - primarySize.width,
            y: footerY,
            width: primarySize.width,
            height: Metrics.buttonHeight
        )

        let dismissSize = dismissButton.fittingSize
        dismissButton.frame = NSRect(
            x: primaryButton.frame.minX - Metrics.footerButtonSpacing - dismissSize.width,
            y: footerY,
            width: dismissSize.width,
            height: Metrics.buttonHeight
        )
    }
}

private extension AppKitComposerOverlayPanelView {
    func configureNavigationButton(_ button: NSButton, symbolName: String, action: Selector) {
        button.isBordered = false
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)
        button.target = self
        button.action = action
        button.setAccessibilityLabel(symbolName == "chevron.left" ? "Previous question" : "Next question")
    }

    func layoutNavigation(contentWidth: CGFloat) {
        guard !pageField.isHidden else {
            previousButton.frame = .zero
            nextButton.frame = .zero
            pageField.frame = .zero
            return
        }
        let buttonSize = Metrics.navigationButtonSize
        let density = configuration?.density ?? Metrics.regularDensity
        let panelPadding = density.panelPadding
        let headerMidY = titleField.frame.isEmpty
            ? density.topPadding + floor(Metrics.headerHeight / 2)
            : titleField.frame.midY
        let buttonY = floor(headerMidY - (buttonSize / 2))
        nextButton.frame = NSRect(
            x: bounds.width - panelPadding - buttonSize,
            y: buttonY,
            width: buttonSize,
            height: buttonSize
        )
        pageField.sizeToFit()
        let pageWidth = max(pageField.fittingSize.width, 40)
        let pageHeight = pageField.fittingSize.height
        pageField.frame = NSRect(
            x: nextButton.frame.minX - pageWidth,
            y: floor(headerMidY - (pageHeight / 2)),
            width: pageWidth,
            height: pageHeight
        )
        previousButton.frame = NSRect(
            x: pageField.frame.minX - buttonSize,
            y: buttonY,
            width: buttonSize,
            height: buttonSize
        )
    }

    var navigationWidth: CGFloat {
        pageField.isHidden ? 0 : 112
    }

    func measuredRowWidth(at index: Int, contentWidth: CGFloat) -> CGFloat {
        guard let configuration,
              configuration.density.placesFooterInlineWithLastRow,
              let lastIndex = rowViews.indices.last,
              index == lastIndex else {
            return contentWidth
        }
        let reservedFooterWidth = dismissButton.fittingSize.width +
            Metrics.footerButtonSpacing +
            primaryButton.fittingSize.width +
            Metrics.footerButtonSpacing
        return max(contentWidth - reservedFooterWidth, 0)
    }

    func wrappedFrame(for field: NSTextField, originX: CGFloat, originY: CGFloat, width: CGFloat) -> NSRect {
        guard width > 0 else {
            return NSRect(x: originX, y: originY, width: 0, height: 0)
        }
        let height = appKitPromptWrappedTextHeight(for: field, width: width)
        return NSRect(x: originX, y: originY, width: width, height: height)
    }

    func updateAppearance() {
        backgroundView.setLayerFillColorPreservingResolvedAlpha { appearance in
            BlockInputComposerStyle.editorFillColor.resolved(for: appearance)
        }
        backgroundView.setLayerStrokeColorPreservingResolvedAlpha { appearance in
            NSColor.separatorColor.resolved(for: appearance)
        }
    }

    func invalidatePreferredSize(force: Bool) {
        let height = measuredHeight(width: bounds.width)
        guard force || abs(height - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = height
        invalidateIntrinsicContentSize()
        onPreferredSizeInvalidated?()
    }

    @objc func handlePrevious() {
        configuration?.onNavigateBackward()
    }

    @objc func handleNext() {
        configuration?.onNavigateForward()
    }

    @objc func handleDismiss() {
        configuration?.onDismiss()
    }

    @objc func handlePrimary() {
        guard configuration?.isPrimaryEnabled == true else {
            return
        }
        configuration?.onPrimary()
    }
}
