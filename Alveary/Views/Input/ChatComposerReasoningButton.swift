import AppKit

@MainActor
final class ComposerReasoningButton: ComposerCompactDropdownButton {
    static let minWidth: CGFloat = 64
    static let maxWidth: CGFloat = 180

    private static let progressIndicatorSize: CGFloat = 12

    private var selection: ChatComposerActionRowView.ReasoningSelection?
    private var showsProgress = false
    private let progressIndicator = NSProgressIndicator()

    override var minimumDropdownWidth: CGFloat { Self.minWidth }
    override var maximumDropdownWidth: CGFloat { Self.maxWidth }
    override var chevronSlotWidth: CGFloat { 16 }
    override var drawsChevron: Bool { !showsProgress }
    override var measuredContentWidth: CGFloat { measuredLabelWidth }

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
        updateProgressIndicator()
    }

    #if DEBUG
    var debugShowsProgress: Bool { showsProgress && !progressIndicator.isHidden }
    var debugTextAlpha: CGFloat { reasoningTextAlpha }
    #endif

    override func layout() {
        super.layout()
        progressIndicator.frame = NSRect(
            x: bounds.maxX - horizontalPadding - Self.progressIndicatorSize,
            y: floor((bounds.height - Self.progressIndicatorSize) / 2),
            width: Self.progressIndicatorSize,
            height: Self.progressIndicatorSize
        )
    }

    override func drawContent(in rect: NSRect) {
        guard let selection else {
            return
        }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        let modelAttributes: [NSAttributedString.Key: Any] = [
            .font: modelFont,
            .foregroundColor: NSColor.labelColor.appKitResolvedColor(in: self, alpha: reasoningTextAlpha),
            .paragraphStyle: paragraph
        ]
        let effortAttributes: [NSAttributedString.Key: Any] = [
            .font: effortFont,
            .foregroundColor: NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: reasoningSubtleTextAlpha),
            .paragraphStyle: paragraph
        ]
        let modelHeight = selection.modelTitle.size(withAttributes: modelAttributes).height
        let labelY = floor((bounds.height - modelHeight) / 2)

        if selection.effortOptions.isEmpty {
            (selection.modelTitle as NSString).draw(
                in: NSRect(x: rect.minX, y: labelY, width: rect.width, height: modelHeight),
                withAttributes: modelAttributes
            )
            return
        }

        let effortWidth = ceil(selection.effortTitle.size(withAttributes: effortAttributes).width)
        let effortX = max(rect.minX, rect.maxX - effortWidth)
        let modelWidth = max(0, effortX - rect.minX - 6)
        (selection.modelTitle as NSString).draw(
            in: NSRect(x: rect.minX, y: labelY, width: modelWidth, height: modelHeight),
            withAttributes: modelAttributes
        )
        (selection.effortTitle as NSString).draw(
            in: NSRect(x: effortX, y: labelY, width: effortWidth, height: modelHeight),
            withAttributes: effortAttributes
        )
    }

    private var measuredLabelWidth: CGFloat {
        guard let selection else {
            return 0
        }
        let modelWidth = selection.modelTitle.size(withAttributes: [.font: modelFont]).width
        guard !selection.effortOptions.isEmpty else {
            return modelWidth
        }
        let effortWidth = selection.effortTitle.size(withAttributes: [.font: effortFont]).width
        return modelWidth + 6 + effortWidth
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

    private func setupReasoningButton() {
        setAccessibilityLabel("Reasoning")
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = false
        progressIndicator.isHidden = true
        addSubview(progressIndicator)
    }

    private func updateProgressIndicator() {
        progressIndicator.isHidden = !showsProgress
        if showsProgress {
            progressIndicator.startAnimation(nil)
        } else {
            progressIndicator.stopAnimation(nil)
        }
        needsLayout = true
    }
}
