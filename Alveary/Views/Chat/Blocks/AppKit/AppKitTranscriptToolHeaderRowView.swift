@preconcurrency import AppKit
import Foundation
import QuartzCore

let appKitTranscriptToolStatusSlotTextOffset: CGFloat = -4
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
        let maxWidth: CGFloat
        let summaryMaximumNumberOfLines: Int
        let showsStatusSlot: Bool

        init(
            summary: String,
            leadingIcon: TranscriptToolLeadingIconKind,
            phase: ToolStatusPhase,
            isExpanded: Bool? = nil,
            showsLeadingIcon: Bool = true,
            debounceStatus: Bool = false,
            typography: TranscriptTypography = TranscriptTypography(),
            bottomPadding: CGFloat = transcriptInlineToolRowVerticalPadding,
            maxWidth: CGFloat = .infinity,
            summaryMaximumNumberOfLines: Int = 1,
            showsStatusSlot: Bool = true
        ) {
            self.summary = summary
            self.leadingIcon = leadingIcon
            self.phase = phase
            self.isExpanded = isExpanded
            self.showsLeadingIcon = showsLeadingIcon
            self.debounceStatus = debounceStatus
            self.typography = typography
            self.bottomPadding = bottomPadding
            self.maxWidth = maxWidth
            self.summaryMaximumNumberOfLines = summaryMaximumNumberOfLines
            self.showsStatusSlot = showsStatusSlot
        }
    }

    var onToggle: (() -> Void)?
    var onHeightInvalidated: (() -> Void)?

    let iconView = AppKitDynamicTintImageView()
    let summaryField = NSTextField(labelWithString: "")
    let summaryPulseField = NSTextField(labelWithString: "")
    let summaryPulseMask = CAGradientLayer()
    let statusView = AppKitTranscriptToolStatusIndicatorView()
    var configuration: Configuration?
    private var isRowHovered = false
    private var trackingArea: NSTrackingArea?
    var lastMeasuredHeight: CGFloat = -1

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
        updateSummaryLineMode(for: configuration)
        updateIcon()
        updateSummary()
        statusView.isHidden = !configuration.showsStatusSlot
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

    func restartSummaryPulseIfNeeded() {
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
        summaryPulseMask.locations
    }

    func setRowHoveredForTesting(_ hovered: Bool, animated: Bool = false) {
        setRowHovered(hovered, animated: animated)
    }

    func setDisclosureHoveredForTesting(_ hovered: Bool, animated: Bool = false) {
        setRowHovered(hovered, animated: animated)
    }
}
#endif
