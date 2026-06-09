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
    static let width: CGFloat = 244
    static let modelWidth: CGFloat = 260
    static let speedWidth: CGFloat = 172
    static let maxModelHeight: CGFloat = 360
    static let horizontalInset: CGFloat = 6
    static let verticalInset: CGFloat = 8
    static let headerInset: CGFloat = 18
    // Headers bottom-align within their own rows; this spacing is the visual
    // inset before the selectable rows that follow.
    static let headerHeight: CGFloat = 18
    static let headerBottomSpacing: CGFloat = 4
    static let rowHeight: CGFloat = 32
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
    static func mainContentSize(for configuration: ChatComposerActionRowView.ReasoningConfiguration) -> NSSize {
        let effortCount = configuration.selection.effortOptions.count
        let variableHeight: CGFloat
        if effortCount == 0 {
            variableHeight = 0
        } else {
            variableHeight = rowHeight * CGFloat(effortCount) +
                dividerSpacing + AppKitComposerPopoverDividerView.height + dividerSpacing
        }
        return NSSize(
            width: width,
            height: verticalInset * 2 +
                headerHeight + headerBottomSpacing +
                variableHeight +
                headerHeight + headerBottomSpacing +
                rowHeight +
                (configuration.selection.supportsSpeedMode ? rowHeight : 0)
        )
    }

    static func speedContentSize() -> NSSize {
        NSSize(
            width: speedWidth,
            height: verticalInset * 2 + rowHeight * CGFloat(AgentSpeedMode.allCases.count)
        )
    }

    @MainActor
    static func modelContentSize(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        showsProviderHeaders: Bool
    ) -> NSSize {
        NSSize(
            width: modelWidth,
            height: min(maxModelHeight, modelDocumentHeight(groups: groups, showsProviderHeaders: showsProviderHeaders))
        )
    }

    @MainActor
    static func modelDocumentHeight(
        groups: [ChatComposerActionRowView.ReasoningModelGroup],
        showsProviderHeaders: Bool
    ) -> CGFloat {
        let modelCount = max(1, groups.flatMap(\.options).count)
        let headerCount = showsProviderHeaders ? groups.filter { $0.providerTitle != nil }.count : 0
        let dividerCount = showsProviderHeaders ? max(0, groups.count - 1) : 0
        return verticalInset * 2 +
            rowHeight * CGFloat(modelCount) +
            (headerHeight + headerBottomSpacing) * CGFloat(headerCount) +
            (AppKitComposerPopoverDividerView.height + dividerSpacing * 2) * CGFloat(dividerCount)
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
            ComposerReasoningMenuMetrics.verticalInset
        )
    }
}
