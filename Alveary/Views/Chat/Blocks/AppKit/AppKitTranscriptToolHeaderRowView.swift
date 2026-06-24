@preconcurrency import AppKit
import Foundation
import QuartzCore

private let appKitTranscriptToolStatusSlotTextOffset: CGFloat = -4
private let appKitToolSummaryPulseAnimationKey = "toolSummaryPulse"
private let appKitToolSummaryPulseDuration: CFTimeInterval = 1.45
private let appKitToolSummaryPulseBaseLocations: [NSNumber] = [0.06, 0.24, 0.42, 0.60, 0.78]
private let appKitToolSummaryPulseStartLocations: [NSNumber] = [-0.42, -0.24, -0.06, 0.12, 0.30]
private let appKitToolSummaryPulseEndLocations: [NSNumber] = [0.70, 0.88, 1.06, 1.24, 1.42]

@MainActor
final class AppKitTranscriptToolHeaderRowView: NSView {
    struct Configuration: Equatable {
        let summary: String
        let leadingIcon: TranscriptToolLeadingIconKind
        let phase: ToolStatusPhase
        let isExpanded: Bool?
        let showsLeadingIcon: Bool
        let debounceStatus: Bool
        let typography: TranscriptTypography
        let bottomPadding: CGFloat

        init(
            summary: String,
            leadingIcon: TranscriptToolLeadingIconKind,
            phase: ToolStatusPhase,
            isExpanded: Bool? = nil,
            showsLeadingIcon: Bool = true,
            debounceStatus: Bool = false,
            typography: TranscriptTypography = TranscriptTypography(),
            bottomPadding: CGFloat = transcriptInlineToolRowVerticalPadding
        ) {
            self.summary = summary
            self.leadingIcon = leadingIcon
            self.phase = phase
            self.isExpanded = isExpanded
            self.showsLeadingIcon = showsLeadingIcon
            self.debounceStatus = debounceStatus
            self.typography = typography
            self.bottomPadding = bottomPadding
        }
    }

    var onToggle: (() -> Void)?
    var onHeightInvalidated: (() -> Void)?

    private let iconView = AppKitDynamicTintImageView()
    private let summaryField = NSTextField(labelWithString: "")
    private let summaryPulseField = NSTextField(labelWithString: "")
    private let summaryPulseMask = CAGradientLayer()
    private let statusView = AppKitTranscriptToolStatusIndicatorView()
    private var configuration: Configuration?
    private var isRowHovered = false
    private var trackingArea: NSTrackingArea?
    private var lastMeasuredHeight: CGFloat = -1

    private var isDisclosureHovered: Bool {
        configuration?.isExpanded != nil && isRowHovered
    }

    private var currentForegroundColor: NSColor {
        transcriptInlineToolRowForegroundColor(isHovered: isRowHovered)
    }

    private var currentPulseHighlightColor: NSColor {
        transcriptInlineToolRowPulseHighlightColor(isHovered: isRowHovered)
    }

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
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight())
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        updateIcon()
        updateSummary()
        statusView.configure(
            phase: configuration.phase,
            debounceTerminal: configuration.debounceStatus,
            typography: configuration.typography,
            disclosureExpansionState: configuration.isExpanded,
            disclosureHovered: isDisclosureHovered
        )
        refreshHoverTrackingArea()
        updateAccessibility(for: configuration)
        needsLayout = true
        invalidateTranscriptHeight(force: true)
    }

    override func layout() {
        layoutContent()
        super.layout()
        invalidateTranscriptHeight(force: false)
    }

    override func mouseDown(with event: NSEvent) {
        if onToggle != nil {
            onToggle?()
        } else {
            super.mouseDown(with: event)
        }
    }

    override func accessibilityPerformPress() -> Bool {
        guard let onToggle else {
            return false
        }
        onToggle()
        return true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateSummary()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            self?.restartSummaryPulseIfNeeded()
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshHoverTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        setRowHovered(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        setRowHovered(false, animated: true)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        iconView.translatesAutoresizingMaskIntoConstraints = true
        iconView.wantsLayer = true
        summaryField.translatesAutoresizingMaskIntoConstraints = true
        summaryField.lineBreakMode = .byTruncatingMiddle
        summaryField.maximumNumberOfLines = 1
        summaryPulseField.translatesAutoresizingMaskIntoConstraints = true
        summaryPulseField.lineBreakMode = .byTruncatingMiddle
        summaryPulseField.maximumNumberOfLines = 1
        summaryPulseField.wantsLayer = true
        summaryPulseField.isHidden = true
        summaryPulseField.setAccessibilityElement(false)
        summaryPulseMask.startPoint = CGPoint(x: 0, y: 0.5)
        summaryPulseMask.endPoint = CGPoint(x: 1, y: 0.5)
        summaryPulseMask.colors = [
            NSColor.clear.cgColor,
            NSColor.black.withAlphaComponent(0.22).cgColor,
            NSColor.black.withAlphaComponent(0.92).cgColor,
            NSColor.black.withAlphaComponent(0.22).cgColor,
            NSColor.clear.cgColor
        ]
        summaryPulseMask.locations = appKitToolSummaryPulseBaseLocations
        summaryPulseField.layer?.mask = summaryPulseMask
        statusView.translatesAutoresizingMaskIntoConstraints = true
        statusView.onPress = { [weak self] in
            self?.onToggle?()
        }
        addSubview(iconView)
        addSubview(summaryField)
        addSubview(summaryPulseField)
        addSubview(statusView)
    }

    private func updateAccessibility(for configuration: Configuration) {
        setAccessibilityRole(onToggle == nil ? .group : .button)
        setAccessibilityLabel(configuration.summary)
        setAccessibilityValue(configuration.isExpanded.map { $0 ? "expanded" : "collapsed" })
    }

    private func updateIcon() {
        guard let configuration else {
            return
        }
        iconView.isHidden = !configuration.showsLeadingIcon
        let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
        iconView.image = NSImage(systemSymbolName: systemSymbolName(for: configuration.leadingIcon), accessibilityDescription: nil)
        updateIconTint()
        iconView.symbolConfiguration = .init(pointSize: metrics.leadingIconSize, weight: .heavy)
        iconView.layer?.setAffineTransform(.identity)
    }

    private func updateIconTint() {
        iconView.setDynamicContentTintColorPreservingAlpha(currentForegroundColor)
    }

    private func updateSummary() {
        guard let configuration else {
            return
        }
        summaryField.attributedStringValue = TranscriptToolSummaryFormatter.nsAttributedString(
            configuration.summary,
            typography: configuration.typography,
            foregroundColor: currentForegroundColor
        )
        summaryPulseField.attributedStringValue = pulseAttributedSummary(for: configuration)
        updateSummaryPulseVisibility()
    }

    private func setRowHovered(_ hovered: Bool, animated: Bool) {
        guard isRowHovered != hovered else {
            return
        }
        isRowHovered = hovered
        updateIconTint()
        updateSummary()
        updateStatusView(animated: animated)
    }

    private func updateStatusView(animated: Bool) {
        guard let configuration else {
            return
        }
        statusView.configure(
            phase: configuration.phase,
            debounceTerminal: configuration.debounceStatus,
            typography: configuration.typography,
            disclosureExpansionState: configuration.isExpanded,
            disclosureHovered: isDisclosureHovered,
            animateDisclosureChange: animated
        )
    }

    private func refreshHoverTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        guard configuration != nil else {
            isRowHovered = false
            return
        }
        let newTrackingArea = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(newTrackingArea)
        trackingArea = newTrackingArea
    }

    private func layoutContent() {
        guard let configuration else {
            return
        }
        let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
        let contentY = transcriptInlineToolRowVerticalPadding
        let contentHeight = max(
            metrics.controlSize,
            ceil(summaryField.fittingSize.height)
        )
        if configuration.showsLeadingIcon {
            iconView.frame = NSRect(
                x: 0,
                y: contentY + ((contentHeight - metrics.controlSize) / 2),
                width: metrics.controlSize,
                height: metrics.controlSize
            )
        } else {
            iconView.frame = .zero
        }

        let leadingTextInset = configuration.showsLeadingIcon ? metrics.leadingTextInset : 0
        let availableSummaryWidth = max(
            bounds.width - leadingTextInset - metrics.textStatusSpacing - metrics.controlSize,
            0
        )
        let summaryWidth = measuredSummaryWidth(maxWidth: availableSummaryWidth, height: contentHeight)
        let statusX = max(0, min(
            leadingTextInset + summaryWidth + metrics.textStatusSpacing + appKitTranscriptToolStatusSlotTextOffset,
            bounds.width - metrics.controlSize
        ))
        summaryField.frame = NSRect(
            x: leadingTextInset,
            y: contentY + ((contentHeight - ceil(summaryField.fittingSize.height)) / 2),
            width: summaryWidth,
            height: ceil(summaryField.fittingSize.height)
        )
        summaryPulseField.frame = summaryField.frame
        summaryPulseMask.frame = summaryPulseField.bounds
        statusView.frame = NSRect(
            x: statusX,
            y: contentY + ((contentHeight - metrics.controlSize) / 2),
            width: metrics.controlSize,
            height: metrics.controlSize
        )

        frame.size.height = measuredHeight(for: configuration)
        restartSummaryPulseIfNeeded()
    }

    private func pulseAttributedSummary(for configuration: Configuration) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            attributedString: TranscriptToolSummaryFormatter.nsAttributedString(
                configuration.summary,
                typography: configuration.typography,
                foregroundColor: currentPulseHighlightColor
            )
        )
        attributed.removeAttribute(.backgroundColor, range: NSRange(location: 0, length: attributed.length))
        return attributed
    }

    private func updateSummaryPulseVisibility() {
        guard configuration?.phase == .loading else {
            summaryPulseField.isHidden = true
            summaryPulseMask.removeAnimation(forKey: appKitToolSummaryPulseAnimationKey)
            return
        }
        summaryPulseField.isHidden = false
        restartSummaryPulseIfNeeded()
    }

    private func restartSummaryPulseIfNeeded() {
        guard !summaryPulseField.isHidden,
              summaryPulseField.bounds.width > 0,
              window != nil,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            summaryPulseMask.removeAnimation(forKey: appKitToolSummaryPulseAnimationKey)
            return
        }
        guard summaryPulseMask.animation(forKey: appKitToolSummaryPulseAnimationKey) == nil else {
            return
        }
        summaryPulseMask.locations = appKitToolSummaryPulseBaseLocations
        let animation = CAKeyframeAnimation(keyPath: "locations")
        animation.values = [
            appKitToolSummaryPulseStartLocations,
            appKitToolSummaryPulseEndLocations,
            appKitToolSummaryPulseEndLocations
        ]
        animation.keyTimes = [0, 0.82, 1]
        animation.duration = appKitToolSummaryPulseDuration
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeInEaseOut),
            CAMediaTimingFunction(name: .linear)
        ]
        animation.repeatCount = .infinity
        animation.isRemovedOnCompletion = false
        summaryPulseMask.add(animation, forKey: appKitToolSummaryPulseAnimationKey)
    }

    private func measuredSummaryWidth(maxWidth: CGFloat, height: CGFloat) -> CGFloat {
        guard maxWidth > 0 else {
            return 0
        }
        let naturalWidth = ceil(summaryField.fittingSize.width)
        let proposedWidth = min(naturalWidth, maxWidth)
        let proposedBounds = NSRect(x: 0, y: 0, width: proposedWidth, height: height)
        let cellWidth = summaryField.cell.map { ceil($0.cellSize(forBounds: proposedBounds).width) } ?? proposedWidth
        return min(max(cellWidth, 0), proposedWidth)
    }

    private func measuredHeight() -> CGFloat {
        guard let configuration else {
            return 0
        }
        return measuredHeight(for: configuration)
    }

    private func measuredHeight(for configuration: Configuration) -> CGFloat {
        let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
        return transcriptInlineToolRowVerticalPadding
            + max(metrics.controlSize, ceil(summaryField.fittingSize.height))
            + configuration.bottomPadding
    }

    private func invalidateTranscriptHeight(force: Bool) {
        let newHeight = measuredHeight()
        guard force || abs(newHeight - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = newHeight
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }

    // Keep this switch exhaustive so new semantic icon cases cannot silently fall back to a generic glyph.
    // swiftlint:disable:next cyclomatic_complexity
    private func systemSymbolName(for kind: TranscriptToolLeadingIconKind) -> String {
        switch kind {
        case .terminal:
            return "terminal"
        case .search:
            return "magnifyingglass"
        case .folder:
            return "folder"
        case .read:
            return "magnifyingglass"
        case .book:
            return "book"
        case .document:
            return "doc.text"
        case .edit:
            return "pencil"
        case .write:
            return "pencil"
        case .skill:
            return "book"
        case .checklist:
            return "checklist"
        case .question:
            return "questionmark"
        case .subAgent:
            return "hat.widebrim"
        case .toolGroup:
            return "wrench.and.screwdriver"
        case .genericTool:
            return "gearshape"
        }
    }
}

#if DEBUG
extension AppKitTranscriptToolHeaderRowView {
    var leadingIconSystemNameForTesting: String? {
        configuration.map { systemSymbolName(for: $0.leadingIcon) }
    }

    var showsLeadingIconForTesting: Bool {
        configuration?.showsLeadingIcon == true
    }

    var isSummaryPulseVisibleForTesting: Bool {
        !summaryPulseField.isHidden
    }

    var summaryPulseHighlightColorForTesting: NSColor? {
        let attributed = summaryPulseField.attributedStringValue
        guard attributed.length > 0 else {
            return nil
        }
        return attributed.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? NSColor
    }

    var summaryPulseMaskLocationsForTesting: [NSNumber]? {
        summaryPulseMask.locations as? [NSNumber]
    }

    func setRowHoveredForTesting(_ hovered: Bool, animated: Bool = false) {
        setRowHovered(hovered, animated: animated)
    }

    func setDisclosureHoveredForTesting(_ hovered: Bool, animated: Bool = false) {
        setRowHovered(hovered, animated: animated)
    }
}
#endif

private func transcriptInlineToolRowPulseHighlightColor(isHovered: Bool) -> NSColor {
    let baseColor = transcriptInlineToolRowForegroundColor(isHovered: isHovered)
    return NSColor(name: nil) { appearance in
        let base = baseColor.resolved(for: appearance)
        let label = NSColor.labelColor.resolved(for: appearance)
        return base.interpolated(toward: label, amount: 0.45)
    }
}

private extension NSColor {
    func interpolated(toward target: NSColor, amount: CGFloat) -> NSColor {
        guard let sourceRGB = usingColorSpace(.deviceRGB),
              let targetRGB = target.usingColorSpace(.deviceRGB) else {
            return target
        }
        let clampedAmount = min(max(amount, 0), 1)
        return NSColor(
            deviceRed: sourceRGB.redComponent + ((targetRGB.redComponent - sourceRGB.redComponent) * clampedAmount),
            green: sourceRGB.greenComponent + ((targetRGB.greenComponent - sourceRGB.greenComponent) * clampedAmount),
            blue: sourceRGB.blueComponent + ((targetRGB.blueComponent - sourceRGB.blueComponent) * clampedAmount),
            alpha: sourceRGB.alphaComponent + ((targetRGB.alphaComponent - sourceRGB.alphaComponent) * clampedAmount)
        )
    }
}
