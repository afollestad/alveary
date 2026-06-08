import AppKit

/// Native context-window meter used by AppKit composer controls.
///
/// Keep this native so the composer action row does not embed SwiftUI islands
/// inside AppKit layout.
@MainActor
final class AppKitContextWindowIndicatorView: NSView {
    static let visibleCircleDiameter: CGFloat = 14

    private var summary: ConversationUsageSummary?
    private var trackingArea: NSTrackingArea?
    private var hoverPopover: NSPopover?
    // Keep the visible ring smaller than the hover target so it matches the
    // SwiftUI indicator while preserving the wider AppKit hit area.
    private let hitTargetSize: CGFloat = 22
    private let strokeWidth: CGFloat = 3

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: hitTargetSize, height: hitTargetSize)
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Context window usage")
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Context window usage")
    }

    func configure(summary: ConversationUsageSummary?) {
        let previousSummary = self.summary
        self.summary = summary
        isHidden = summary == nil
        setAccessibilityValue(summary.map(Self.accessibilityValue(for:)) ?? "")
        if summary == nil {
            closeHoverPopover()
        } else if hoverPopover?.isShown == true, previousSummary != summary {
            updateHoverPopover(with: summary)
        }
        needsDisplay = true
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let newTrackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        trackingArea = newTrackingArea
        addTrackingArea(newTrackingArea)
    }

    override func mouseEntered(with event: NSEvent) {
        showHoverPopover()
    }

    override func mouseExited(with event: NSEvent) {
        closeHoverPopover()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        hoverPopover?.contentViewController?.view.needsDisplay = true
        needsDisplay = true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            closeHoverPopover()
        }
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        if superview == nil {
            closeHoverPopover()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let summary else {
            return
        }

        let circleRect = NSRect(
            x: floor((bounds.width - Self.visibleCircleDiameter) / 2),
            y: floor((bounds.height - Self.visibleCircleDiameter) / 2),
            width: Self.visibleCircleDiameter,
            height: Self.visibleCircleDiameter
        )
        let basePath = NSBezierPath(ovalIn: circleRect.insetBy(dx: strokeWidth / 2, dy: strokeWidth / 2))
        basePath.lineWidth = strokeWidth
        NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 0.28).setStroke()
        basePath.stroke()

        let progressPath = NSBezierPath()
        let radius = (Self.visibleCircleDiameter - strokeWidth) / 2
        let center = NSPoint(x: circleRect.midX, y: circleRect.midY)
        progressPath.appendArc(
            withCenter: center,
            radius: radius,
            startAngle: 90,
            endAngle: 90 - (360 * summary.contextUsageFraction),
            clockwise: true
        )
        progressPath.lineCapStyle = .round
        progressPath.lineWidth = strokeWidth
        progressColor(for: summary).setStroke()
        progressPath.stroke()
    }

    private func progressColor(for summary: ConversationUsageSummary) -> NSColor {
        switch summary.contextUsageFraction {
        case 0.9...:
            return .systemRed
        case 0.75..<0.9:
            return .systemOrange
        default:
            return .secondaryLabelColor.appKitResolvedColor(in: self)
        }
    }

    private func showHoverPopover() {
        guard let summary, window != nil else {
            return
        }
        if hoverPopover?.isShown == true {
            updateHoverPopover(with: summary)
            return
        }
        closeHoverPopover()

        let popover = NSPopover()
        let tooltipView = AppKitContextWindowTooltipView(summary: summary)
        let preferredSize = tooltipView.applyPreferredSize()
        let controller = NSViewController()
        controller.view = tooltipView
        controller.preferredContentSize = preferredSize
        popover.contentViewController = controller
        popover.contentSize = preferredSize
        popover.behavior = .transient
        popover.animates = false
        popover.show(relativeTo: bounds, of: self, preferredEdge: .maxY)
        hoverPopover = popover
    }

    private func updateHoverPopover(with summary: ConversationUsageSummary?) {
        guard let summary,
              let popover = hoverPopover,
              popover.isShown else {
            return
        }
        guard let tooltipView = popover.contentViewController?.view as? AppKitContextWindowTooltipView else {
            closeHoverPopover()
            showHoverPopover()
            return
        }
        tooltipView.update(summary: summary)
        let preferredSize = tooltipView.applyPreferredSize()
        popover.contentViewController?.preferredContentSize = preferredSize
        popover.contentSize = preferredSize
        _ = tooltipView.applyPreferredSize()
    }

    private func closeHoverPopover() {
        hoverPopover?.close()
        hoverPopover = nil
    }

    private static func accessibilityValue(for summary: ConversationUsageSummary) -> String {
        if summary.hasReportedUsage {
            return "\(summary.contextUsagePercent)% full"
        }
        return "No usage reported yet"
    }
}

final class AppKitContextWindowTooltipView: AppKitComposerPopoverSurfaceView {
    private let titleField = NSTextField(labelWithString: "Context window:")
    private let headlineField = NSTextField(labelWithString: "")
    private let detailField = NSTextField(labelWithString: "")
    private let costField = NSTextField(labelWithString: "")
    private let horizontalInset: CGFloat = 16
    private let verticalInset: CGFloat = 16
    private let minimumWidth: CGFloat = 204
    private let titleHeadlineSpacing: CGFloat = 8
    private let bodySpacing: CGFloat = 8

    var preferredSize: NSSize {
        let contentWidth = visibleFields
            .map(Self.singleLineWidth(for:))
            .max() ?? 0
        let costContentHeight = showsCostField ? bodySpacing + costFieldHeight : 0
        return NSSize(
            width: max(minimumWidth, contentWidth + (horizontalInset * 2)),
            height: verticalInset * 2 +
                titleFieldHeight +
                titleHeadlineSpacing +
                headlineFieldHeight +
                bodySpacing +
                detailFieldHeight +
                costContentHeight
        )
    }

    init(summary: ConversationUsageSummary) {
        super.init(frame: .zero)
        setup()
        update(summary: summary)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setup()
    }

    override func layout() {
        super.layout()
        let contentWidth = bounds.width - (horizontalInset * 2)
        var nextY = verticalInset
        titleField.frame = NSRect(x: horizontalInset, y: nextY, width: contentWidth, height: titleFieldHeight)
        nextY += titleFieldHeight + titleHeadlineSpacing
        headlineField.frame = NSRect(x: horizontalInset, y: nextY, width: contentWidth, height: headlineFieldHeight)
        nextY += headlineFieldHeight + bodySpacing
        detailField.frame = NSRect(x: horizontalInset, y: nextY, width: contentWidth, height: detailFieldHeight)
        guard showsCostField else {
            return
        }
        nextY += detailFieldHeight + bodySpacing
        costField.frame = NSRect(x: horizontalInset, y: nextY, width: contentWidth, height: costFieldHeight)
    }

    func update(summary: ConversationUsageSummary) {
        configure(summary: summary)
        needsLayout = true
        needsDisplay = true
    }

    @discardableResult
    func applyPreferredSize() -> NSSize {
        let size = preferredSize
        setFrameSize(size)
        layoutSubtreeIfNeeded()
        return size
    }

    private func setup() {
        [titleField, headlineField, detailField].forEach {
            $0.alignment = .center
            $0.lineBreakMode = .byTruncatingTail
            $0.maximumNumberOfLines = 1
            $0.cell?.usesSingleLineMode = true
            $0.cell?.wraps = false
            addSubview($0)
        }
        costField.alignment = .center
        costField.lineBreakMode = .byTruncatingTail
        costField.maximumNumberOfLines = 1
        costField.cell?.usesSingleLineMode = true
        costField.cell?.wraps = false
        titleField.font = Self.preferredFont(for: .callout, weight: .semibold)
        titleField.textColor = .secondaryLabelColor
        headlineField.font = Self.preferredFont(for: .headline, weight: .semibold)
        headlineField.textColor = .labelColor
        detailField.font = Self.preferredFont(for: .callout, weight: .semibold)
        detailField.textColor = .labelColor
        costField.font = Self.preferredFont(for: .callout, weight: .semibold)
        costField.textColor = .secondaryLabelColor
    }

    private func configure(summary: ConversationUsageSummary) {
        if summary.hasReportedUsage {
            if summary.hasKnownContextWindowSize {
                headlineField.stringValue = "\(summary.contextUsagePercent)% full"
                detailField.stringValue = "\(Self.tokenText(summary.contextUsedTokens)) / \(Self.tokenText(summary.contextWindowSize)) tokens used"
            } else {
                headlineField.stringValue = "Usage reported"
                detailField.stringValue = "\(Self.tokenText(summary.contextUsedTokens)) tokens used"
            }
        } else {
            headlineField.stringValue = "No usage yet"
            if summary.hasKnownContextWindowSize {
                detailField.stringValue = "\(Self.tokenText(summary.contextWindowSize)) token window"
            } else {
                detailField.stringValue = "Context window size not reported"
            }
        }
        if summary.hasReportedCost {
            costField.stringValue = "Session spend: \(Self.costText(summary.totalCostUsd))"
            if costField.superview == nil {
                addSubview(costField)
            }
        } else {
            costField.stringValue = ""
            costField.removeFromSuperview()
        }
    }

    private static func tokenText(_ value: Int) -> String {
        if value >= 1_000_000 {
            return compactDecimal(Double(value) / 1_000_000) + "M"
        }
        if value >= 1_000 {
            return compactDecimal(Double(value) / 1_000) + "k"
        }
        return value.formatted()
    }

    private static func compactDecimal(_ value: Double) -> String {
        if value.rounded() == value {
            return String(Int(value))
        }
        return String(format: "%.1f", value)
    }

    private static func costText(_ value: Double) -> String {
        if value > 0, value < 0.01 {
            return String(format: "$%.4f", value)
        }
        return String(format: "$%.2f", value)
    }

    private static func preferredFont(for textStyle: NSFont.TextStyle, weight: NSFont.Weight) -> NSFont {
        NSFont.systemFont(ofSize: NSFont.preferredFont(forTextStyle: textStyle).pointSize, weight: weight)
    }

    private static func singleLineWidth(for field: NSTextField) -> CGFloat {
        let font = field.font ?? .preferredFont(forTextStyle: .callout)
        let textWidth = (field.stringValue as NSString).size(withAttributes: [.font: font]).width
        let cellWidth = field.cell?.cellSize.width ?? 0
        return ceil(max(textWidth, cellWidth, field.fittingSize.width, field.intrinsicContentSize.width)) + 4
    }

    private var titleFieldHeight: CGFloat {
        ceil(titleField.intrinsicContentSize.height)
    }

    private var headlineFieldHeight: CGFloat {
        ceil(headlineField.intrinsicContentSize.height)
    }

    private var detailFieldHeight: CGFloat {
        ceil(detailField.intrinsicContentSize.height)
    }

    private var costFieldHeight: CGFloat {
        ceil(costField.intrinsicContentSize.height)
    }

    private var visibleFields: [NSTextField] {
        if showsCostField {
            return [titleField, headlineField, detailField, costField]
        }
        return [titleField, headlineField, detailField]
    }

    private var showsCostField: Bool {
        costField.superview != nil
    }
}
