import AppKit

@MainActor
final class ComposerReasoningButton: ComposerCompactDropdownButton {
    static let minWidth: CGFloat = 64
    static let maxWidth: CGFloat = 220

    private static let progressIndicatorSize: CGFloat = 12
    private static let modelEffortSpacing: CGFloat = 2
    private static let effortChevronSpacing: CGFloat = ComposerIconTitleDropdownButton.iconTextSpacing
    private static let textFieldFittingReserve: CGFloat = 2

    private var selection: ChatComposerActionRowView.ReasoningSelection?
    private var showsProgress = false
    private var isModelTitleTruncated = false
    private let fastIconView = NSImageView()
    private let modelLabel = NSTextField(labelWithString: "")
    private let effortLabel = NSTextField(labelWithString: "")
    private let chevronView = NSImageView()
    private let progressIndicator = NSProgressIndicator()

    override var minimumDropdownWidth: CGFloat { Self.minWidth }
    override var maximumDropdownWidth: CGFloat { Self.maxWidth }
    override var reservesTrailingSlot: Bool { false }
    override var drawsChevron: Bool { false }
    override var measuredContentWidth: CGFloat { measuredSpeedIconWidth + measuredLabelWidth }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupReasoningButton()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupReasoningButton()
    }

    func configure(
        selection: ChatComposerActionRowView.ReasoningSelection,
        height: CGFloat,
        isEnabled: Bool,
        showsProgress: Bool,
        actionHandler: @escaping () -> Void
    ) {
        self.selection = selection
        self.showsProgress = showsProgress
        configureBase(height: height, isEnabled: isEnabled, actionHandler: actionHandler)
        setAccessibilityValue(selection.accessibilityValue)
        updateContentPresentation()
        updateProgressIndicator()
    }

    #if DEBUG
    var debugShowsProgress: Bool { showsProgress && !progressIndicator.isHidden }
    var debugTextAlpha: CGFloat { reasoningTextAlpha }
    var debugShowsFastIcon: Bool { showsFastIcon }
    var debugFastIconSlotSize: CGFloat { ComposerIconTitleDropdownButton.iconSlotSize }
    var debugFastIconTextSpacing: CGFloat { ComposerIconTitleDropdownButton.iconTextSpacing }
    var debugFastIconFrame: NSRect? { fastIconView.isHidden ? nil : fastIconView.frame }
    var debugDisplayedModelTitle: String? { modelLabel.stringValue }
    var debugModelFrame: NSRect? { modelLabel.frame }
    var debugEffortFrame: NSRect? { effortLabel.isHidden ? nil : effortLabel.frame }
    var debugChevronFrame: NSRect? { chevronView.isHidden ? nil : chevronView.frame }
    var debugIsModelTruncated: Bool { isModelTitleTruncated }
    var debugModelEffortGap: CGFloat? {
        guard !effortLabel.isHidden, modelLabel.frame.width > 0 else {
            return nil
        }
        return effortLabel.frame.minX - modelLabel.frame.maxX
    }
    var debugEffortChevronGap: CGFloat? {
        guard !effortLabel.isHidden, !chevronView.isHidden else {
            return nil
        }
        return chevronView.frame.minX - effortLabel.frame.maxX
    }
    var debugContentTrailingGap: CGFloat? {
        if !chevronView.isHidden {
            return bounds.maxX - horizontalPadding - chevronView.frame.maxX
        }
        if !progressIndicator.isHidden {
            return bounds.maxX - horizontalPadding - progressIndicator.frame.maxX
        }
        if !effortLabel.isHidden {
            return bounds.maxX - horizontalPadding - effortLabel.frame.maxX
        }
        guard !modelLabel.isHidden else {
            return nil
        }
        return bounds.maxX - horizontalPadding - modelLabel.frame.maxX
    }
    #endif

    override func layout() {
        super.layout()
        layoutContentRow()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard super.hitTest(point) != nil else {
            return nil
        }
        return self
    }

    override func drawContent(in rect: NSRect) {
        // Content is laid out as real subviews so text, icon, and chevron spacing follows row semantics.
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateContentPresentation()
    }

    private var measuredLabelWidth: CGFloat {
        guard let selection else {
            return 0
        }
        let modelWidth = textWidth(selection.modelTitle, attributes: [.font: modelFont])
        let trailingWidth = max(Self.progressIndicatorSize, chevronDrawingWidth)
        let trailingSpacing = Self.effortChevronSpacing + trailingWidth
        guard !selection.effortOptions.isEmpty else {
            return modelWidth + trailingSpacing
        }
        let effortWidth = textWidth(selection.effortTitle, attributes: [.font: effortFont])
        return modelWidth + Self.modelEffortSpacing + effortWidth + trailingSpacing
    }

    private var measuredSpeedIconWidth: CGFloat {
        guard showsFastIcon else {
            return 0
        }
        return fastIconDrawingWidth + ComposerIconTitleDropdownButton.iconTextSpacing
    }

    private var showsFastIcon: Bool {
        selection?.supportsSpeedMode == true && selection?.speedMode == .fast
    }

    private func setupReasoningButton() {
        setAccessibilityLabel("Reasoning")
        configureLabel(modelLabel, font: modelFont, lineBreakMode: .byClipping)
        configureLabel(effortLabel, font: effortFont, lineBreakMode: .byClipping)
        configureImageView(fastIconView)
        configureImageView(chevronView)
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        progressIndicator.setAccessibilityElement(false)
        addSubview(fastIconView)
        addSubview(modelLabel)
        addSubview(effortLabel)
        addSubview(chevronView)
        addSubview(progressIndicator)
        updateContentPresentation()
    }

    private func configureLabel(_ label: NSTextField, font: NSFont, lineBreakMode: NSLineBreakMode) {
        label.font = font
        label.lineBreakMode = lineBreakMode
        label.maximumNumberOfLines = 1
        label.cell?.lineBreakMode = lineBreakMode
        label.cell?.truncatesLastVisibleLine = lineBreakMode == .byTruncatingTail
        label.cell?.usesSingleLineMode = true
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        label.setContentHuggingPriority(.defaultLow, for: .horizontal)
        label.setAccessibilityElement(false)
    }

    private func configureImageView(_ imageView: NSImageView) {
        imageView.imageAlignment = .alignCenter
        imageView.imageScaling = .scaleProportionallyDown
        imageView.setAccessibilityElement(false)
    }

    private func updateContentPresentation() {
        guard let selection else {
            fastIconView.isHidden = true
            modelLabel.isHidden = true
            effortLabel.isHidden = true
            chevronView.isHidden = true
            isModelTitleTruncated = false
            return
        }
        modelLabel.isHidden = false
        modelLabel.stringValue = selection.modelTitle
        modelLabel.textColor = NSColor.labelColor.appKitResolvedColor(in: self, alpha: reasoningTextAlpha)
        effortLabel.isHidden = selection.effortOptions.isEmpty
        effortLabel.stringValue = selection.effortTitle
        effortLabel.textColor = NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: reasoningSubtleTextAlpha)
        fastIconView.isHidden = !showsFastIcon
        fastIconView.image = fastIconImage()
        chevronView.isHidden = showsProgress
        chevronView.image = chevronImage()
        needsLayout = true
    }

    private func layoutContentRow() {
        guard let selection else {
            resetContentFrames()
            return
        }

        let contentRect = contentRowRect
        let trailingWidth = showsProgress ? Self.progressIndicatorSize : chevronDrawingWidth
        let naturalEffortWidth = selection.effortOptions.isEmpty
            ? 0
            : textWidth(selection.effortTitle, attributes: [.font: effortFont])
        let modelStartX = modelLeadingX(in: contentRect)
        let effortSpacing = selection.effortOptions.isEmpty ? 0 : Self.modelEffortSpacing
        let fixedTrailingWidth = naturalEffortWidth + effortSpacing + Self.effortChevronSpacing + trailingWidth
        let modelMaxWidth = max(0, contentRect.maxX - modelStartX - fixedTrailingWidth)
        let displayedModelTitle = displayedModelTitle(for: selection.modelTitle, maxWidth: modelMaxWidth)
        let modelWidth = textWidth(displayedModelTitle, attributes: [.font: modelFont])
        var nextX = modelStartX

        modelLabel.stringValue = displayedModelTitle
        isModelTitleTruncated = displayedModelTitle != selection.modelTitle
        modelLabel.frame = centeredFrame(
            originX: nextX,
            width: modelWidth,
            height: textHeight(for: modelLabel),
            in: contentRect
        )
        nextX = modelLabel.frame.maxX

        layoutEffortLabel(
            hasEffort: !selection.effortOptions.isEmpty,
            modelWidth: modelWidth,
            effortWidth: naturalEffortWidth,
            nextX: &nextX,
            contentRect: contentRect
        )

        layoutTrailingAccessory(at: nextX + Self.effortChevronSpacing, width: trailingWidth, in: contentRect)
    }

    private var contentRowRect: NSRect {
        NSRect(
            x: horizontalPadding,
            y: 0,
            width: max(0, bounds.width - horizontalPadding * 2),
            height: bounds.height
        )
    }

    private func resetContentFrames() {
        fastIconView.frame = .zero
        modelLabel.frame = .zero
        effortLabel.frame = .zero
        chevronView.frame = .zero
        progressIndicator.frame = .zero
    }

    private func layoutEffortLabel(
        hasEffort: Bool,
        modelWidth: CGFloat,
        effortWidth: CGFloat,
        nextX: inout CGFloat,
        contentRect: NSRect
    ) {
        guard hasEffort else {
            effortLabel.frame = .zero
            return
        }
        if modelWidth > 0 {
            nextX += Self.modelEffortSpacing
        }
        effortLabel.frame = centeredFrame(
            originX: nextX,
            width: effortWidth,
            height: textHeight(for: effortLabel),
            in: contentRect
        )
        nextX = effortLabel.frame.maxX
    }

    private func layoutTrailingAccessory(at originX: CGFloat, width: CGFloat, in contentRect: NSRect) {
        if showsProgress {
            progressIndicator.frame = centeredFrame(
                originX: originX,
                width: Self.progressIndicatorSize,
                height: Self.progressIndicatorSize,
                in: contentRect
            )
            chevronView.frame = .zero
        } else {
            chevronView.frame = centeredFrame(
                originX: originX,
                width: width,
                height: chevronMaxSize,
                in: contentRect
            )
            progressIndicator.frame = .zero
        }
    }

    private func modelLeadingX(in contentRect: NSRect) -> CGFloat {
        guard showsFastIcon else {
            fastIconView.frame = .zero
            return contentRect.minX
        }
        fastIconView.frame = centeredFrame(
            originX: contentRect.minX,
            width: fastIconDrawingWidth,
            height: ComposerIconTitleDropdownButton.iconSlotSize,
            in: contentRect
        )
        return fastIconView.frame.maxX + ComposerIconTitleDropdownButton.iconTextSpacing
    }

    private func fastIconImage() -> NSImage? {
        let color = NSColor.labelColor.appKitResolvedColor(in: self, alpha: reasoningTextAlpha)
        return symbolImage(
            named: "bolt",
            pointSize: ComposerIconTitleDropdownButton.iconPointSize,
            color: color,
            weight: .semibold
        )
    }

    private var fastIconDrawingWidth: CGFloat {
        guard let image = fastIconImage() else {
            return ComposerIconTitleDropdownButton.iconSlotSize
        }
        return symbolDrawingSize(
            for: image,
            maxSize: ComposerIconTitleDropdownButton.iconSlotSize
        ).width
    }

    private func chevronImage() -> NSImage? {
        symbolImage(named: "chevron.down", pointSize: chevronMaxSize, color: chevronColor)
    }

    private var chevronDrawingWidth: CGFloat {
        guard let image = chevronImage() else {
            return chevronMaxSize
        }
        return symbolDrawingSize(for: image, maxSize: chevronMaxSize).width
    }

    private func textHeight(for label: NSTextField) -> CGFloat {
        let measuredHeight = textSize(label.stringValue, attributes: [.font: label.font ?? modelFont]).height
        return ceil(max(label.intrinsicContentSize.height, measuredHeight))
    }

    private func centeredFrame(originX: CGFloat, width: CGFloat, height: CGFloat, in rect: NSRect) -> NSRect {
        NSRect(
            x: floor(originX),
            y: floor((rect.height - height) / 2),
            width: max(0, ceil(width)),
            height: height
        )
    }

    private func displayedModelTitle(for title: String, maxWidth: CGFloat) -> String {
        guard maxWidth >= minimumVisibleModelWidth else {
            return ""
        }
        guard textWidth(title, attributes: [.font: modelFont]) > maxWidth else {
            return title
        }

        let characters = Array(title)
        var lowerBound = 0
        var upperBound = characters.count
        var bestFit = "…"
        while lowerBound <= upperBound {
            let midpoint = (lowerBound + upperBound) / 2
            let candidate = String(characters.prefix(midpoint)) + "…"
            if textWidth(candidate, attributes: [.font: modelFont]) <= maxWidth {
                bestFit = candidate
                lowerBound = midpoint + 1
            } else {
                upperBound = midpoint - 1
            }
        }
        return bestFit
    }

    private var minimumVisibleModelWidth: CGFloat {
        textWidth("…", attributes: [.font: modelFont])
    }

    private func textWidth(_ text: String, attributes: [NSAttributedString.Key: Any]) -> CGFloat {
        guard !text.isEmpty else {
            return 0
        }
        return ceil(textSize(text, attributes: attributes).width + Self.textFieldFittingReserve)
    }

    private func textSize(_ text: String, attributes: [NSAttributedString.Key: Any]) -> NSSize {
        (text as NSString).size(withAttributes: attributes)
    }

    private var modelFont: NSFont {
        NSFontManager.shared.convert(NSFont.preferredFont(forTextStyle: .body), toHaveTrait: .boldFontMask)
    }

    private var effortFont: NSFont {
        NSFont.preferredFont(forTextStyle: .body)
    }

    private var reasoningTextAlpha: CGFloat {
        controlIsEnabled || showsProgress ? 0.9 : 0.26
    }

    private var reasoningSubtleTextAlpha: CGFloat {
        controlIsEnabled || showsProgress ? 0.62 : 0.22
    }

    private func updateProgressIndicator() {
        progressIndicator.isHidden = !showsProgress
        if showsProgress {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
        chevronView.isHidden = showsProgress
        needsLayout = true
    }
}
