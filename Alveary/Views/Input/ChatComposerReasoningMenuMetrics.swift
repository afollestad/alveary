import AppKit

@MainActor
final class ComposerReasoningHeaderView: NSTextField {
    init(title: String) {
        super.init(frame: .zero)
        stringValue = title
        isEditable = false
        isBordered = false
        drawsBackground = false
        font = .preferredFont(forTextStyle: .caption1)
        textColor = .secondaryLabelColor
        setAccessibilityElement(false)
    }

    override var isFlipped: Bool { true }

    required init?(coder: NSCoder) {
        nil
    }

    #if DEBUG
    var debugTitleDrawingRect: NSRect {
        titleDrawingRect(with: titleAttributes)
    }
    #endif

    override func draw(_ dirtyRect: NSRect) {
        let attributes = titleAttributes
        (stringValue as NSString).draw(in: titleDrawingRect(with: attributes), withAttributes: attributes)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    private var titleAttributes: [NSAttributedString.Key: Any] {
        [
            .font: font ?? .preferredFont(forTextStyle: .caption1),
            .foregroundColor: NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 1),
            .paragraphStyle: ComposerReasoningMenuMetrics.truncatingParagraphStyle
        ]
    }

    private func titleDrawingRect(with attributes: [NSAttributedString.Key: Any]) -> NSRect {
        let titleSize = stringValue.size(withAttributes: attributes)
        return NSRect(
            x: 0,
            y: max(0, floor(bounds.height - titleSize.height)),
            width: bounds.width,
            height: titleSize.height
        )
    }
}

enum ComposerReasoningMenuMetrics {
    static let width: CGFloat = 260
    static let maxModelHeight: CGFloat = 360
    static let disclosureAnimationDuration: TimeInterval = 0.16
    static let horizontalInset: CGFloat = 6
    static let topInset: CGFloat = 14
    static let bottomInset: CGFloat = 12
    static let sliderHorizontalInset: CGFloat = 18
    static let sliderHeight = ComposerReasoningEffortSliderMetrics.controlHeight
    static let sliderBottomSpacing: CGFloat = 4
    static let rowHeight: CGFloat = 32
    static let controlsHeight: CGFloat = rowHeight
    static let modelListBottomInset: CGFloat = 8
    static let providerHeaderTopInset: CGFloat = 0
    static let headerlessModelMenuTopInset: CGFloat = 8
    static let headerInset: CGFloat = 18
    // Headers bottom-align within their own rows; this spacing is the visual
    // inset before the selectable rows that follow.
    static let headerHeight: CGFloat = 18
    static let headerBottomSpacing: CGFloat = 4
    static let permissionRowHeight: CGFloat = 50
    static let dividerSpacing: CGFloat = 7
    static let iconOpticalLeadingAdjustment: CGFloat = 3
    static let iconLeading: CGFloat = headerInset - horizontalInset - iconOpticalLeadingAdjustment
    static let iconSlotSize: CGFloat = 20
    static let iconTextSpacing: CGFloat = 6
    static let leadingIconPointSize: CGFloat = 16
    @MainActor static var iconPointSize: CGFloat { SidebarProjectRow.leadingIconFontSize }
    static let titleLeading: CGFloat = headerInset - horizontalInset
    static let iconTitleLeading: CGFloat = iconLeading + iconSlotSize + iconTextSpacing
    static let titleTrailing: CGFloat = headerInset - horizontalInset
    static let trailingIconInset: CGFloat = 10
    static let trailingIconReservedWidth: CGFloat = 30
    static let subtitleSpacing: CGFloat = 2

    @MainActor static var itemFont: NSFont { NSFont.preferredFont(forTextStyle: .body) }
    @MainActor static var subtitleFont: NSFont { NSFont.preferredFont(forTextStyle: .callout) }
    @MainActor static var truncatingParagraphStyle: NSParagraphStyle {
        let style = NSMutableParagraphStyle()
        style.lineBreakMode = .byTruncatingTail
        return style
    }

    @MainActor
    static func mainContentSize(
        for configuration: ChatComposerActionRowView.ReasoningConfiguration,
        isModelsExpanded: Bool = false
    ) -> NSSize {
        let sliderSectionHeight = configuration.selection.effortOptions.isEmpty
            ? 0
            : sliderHeight + sliderBottomSpacing
        let expandedHeight = isModelsExpanded ? modelsSectionHeight(groups: configuration.modelGroups) : 0
        return NSSize(
            width: width,
            height: topInset + bottomInset +
                sliderSectionHeight +
                controlsHeight +
                expandedHeight
        )
    }

    @MainActor
    static func modelsSectionHeight(groups: [ChatComposerActionRowView.ReasoningModelGroup]) -> CGFloat {
        dividerSpacing + AppKitComposerPopoverDividerView.height + dividerSpacing + modelViewportHeight(groups: groups)
    }

    @MainActor
    static func modelViewportHeight(groups: [ChatComposerActionRowView.ReasoningModelGroup]) -> CGFloat {
        min(maxModelHeight, modelDocumentHeight(groups: groups))
    }

    @MainActor
    static func modelDocumentHeight(groups: [ChatComposerActionRowView.ReasoningModelGroup]) -> CGFloat {
        let visibleGroups = groups.filter { !$0.options.isEmpty }
        let modelCount = max(1, visibleGroups.flatMap(\.options).count)
        let showsProviderHeaders = visibleGroups.count > 1
        let headerCount = showsProviderHeaders ? visibleGroups.count : 0
        let dividerCount = showsProviderHeaders ? max(0, visibleGroups.count - 1) : 0
        return modelMenuTopInset(showsProviderHeaders: showsProviderHeaders) +
            modelListBottomInset +
            rowHeight * CGFloat(modelCount) +
            (headerHeight + headerBottomSpacing) * CGFloat(headerCount) +
            (AppKitComposerPopoverDividerView.height + dividerSpacing * 2) * CGFloat(dividerCount)
    }

    static func modelMenuTopInset(showsProviderHeaders: Bool) -> CGFloat {
        showsProviderHeaders ? providerHeaderTopInset : headerlessModelMenuTopInset
    }
}

@MainActor
enum ComposerReasoningPopoverContentFrame {
    static func topAlignedFrame(for view: NSView, size: NSSize) -> NSRect {
        guard let superview = view.superview else {
            return NSRect(origin: .zero, size: size)
        }
        // AppKit's popover host can be a few points taller than the content
        // surface because of chrome/arrow geometry. Align to the usable top so
        // the flipped menu content is not clipped while the host fill stays covered.
        let topInset = hostTopInset(for: superview, contentSize: size)
        let originY = superview.isFlipped
            ? superview.bounds.minY + topInset
            : superview.bounds.maxY - size.height - topInset
        return NSRect(
            x: view.frame.origin.x,
            y: originY,
            width: size.width,
            height: size.height
        )
    }

    static func visibleTopY(in superview: NSView, contentSize: NSSize) -> CGFloat {
        let topInset = hostTopInset(for: superview, contentSize: contentSize)
        return superview.isFlipped
            ? superview.bounds.minY + topInset
            : superview.bounds.maxY - topInset
    }

    private static func hostTopInset(for superview: NSView, contentSize: NSSize) -> CGFloat {
        min(
            max(0, superview.bounds.height - contentSize.height),
            ComposerReasoningMenuMetrics.topInset
        )
    }
}
