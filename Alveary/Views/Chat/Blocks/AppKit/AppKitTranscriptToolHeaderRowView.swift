@preconcurrency import AppKit
import Foundation

@MainActor
final class AppKitTranscriptToolHeaderRowView: NSView {
    struct Configuration: Equatable {
        let summary: String
        let leadingIcon: TranscriptToolLeadingIconKind
        let phase: ToolStatusPhase
        let isExpanded: Bool?
        let debounceStatus: Bool
        let typography: TranscriptTypography
        let bottomPadding: CGFloat

        init(
            summary: String,
            leadingIcon: TranscriptToolLeadingIconKind,
            phase: ToolStatusPhase,
            isExpanded: Bool? = nil,
            debounceStatus: Bool = false,
            typography: TranscriptTypography = TranscriptTypography(),
            bottomPadding: CGFloat = transcriptInlineToolRowVerticalPadding
        ) {
            self.summary = summary
            self.leadingIcon = leadingIcon
            self.phase = phase
            self.isExpanded = isExpanded
            self.debounceStatus = debounceStatus
            self.typography = typography
            self.bottomPadding = bottomPadding
        }
    }

    var onToggle: (() -> Void)?
    var onHeightInvalidated: (() -> Void)?

    private let iconView = AppKitDynamicTintImageView()
    private let summaryField = NSTextField(labelWithString: "")
    private let statusView = AppKitTranscriptToolStatusIndicatorView()
    private var configuration: Configuration?
    private var isDisclosureHovered = false
    private var trackingArea: NSTrackingArea?
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
        refreshDisclosureTrackingArea()
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

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        refreshDisclosureTrackingArea()
    }

    override func mouseEntered(with event: NSEvent) {
        setDisclosureHovered(true, animated: true)
    }

    override func mouseExited(with event: NSEvent) {
        setDisclosureHovered(false, animated: true)
    }

    private func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityElement(true)
        iconView.translatesAutoresizingMaskIntoConstraints = true
        iconView.wantsLayer = true
        summaryField.translatesAutoresizingMaskIntoConstraints = true
        summaryField.lineBreakMode = .byTruncatingMiddle
        summaryField.maximumNumberOfLines = 1
        statusView.translatesAutoresizingMaskIntoConstraints = true
        statusView.onPress = { [weak self] in
            self?.onToggle?()
        }
        addSubview(iconView)
        addSubview(summaryField)
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
        let metrics = transcriptInlineToolRowMetrics(for: configuration.typography)
        iconView.image = NSImage(systemSymbolName: systemSymbolName(for: configuration.leadingIcon), accessibilityDescription: nil)
        iconView.setDynamicContentTintColor(transcriptInlineToolRowColor)
        iconView.symbolConfiguration = .init(pointSize: metrics.leadingIconSize, weight: .regular)
        iconView.layer?.setAffineTransform(.identity)
    }

    private func updateSummary() {
        guard let configuration else {
            return
        }
        summaryField.attributedStringValue = TranscriptToolSummaryFormatter.nsAttributedString(
            configuration.summary,
            typography: configuration.typography
        )
    }

    private func setDisclosureHovered(_ hovered: Bool, animated: Bool) {
        let normalizedHovered = configuration?.isExpanded != nil && hovered
        guard isDisclosureHovered != normalizedHovered else {
            return
        }
        isDisclosureHovered = normalizedHovered
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

    private func refreshDisclosureTrackingArea() {
        if let trackingArea {
            removeTrackingArea(trackingArea)
            self.trackingArea = nil
        }
        guard configuration?.isExpanded != nil else {
            isDisclosureHovered = false
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
        iconView.frame = NSRect(
            x: 0,
            y: contentY + ((contentHeight - metrics.controlSize) / 2),
            width: metrics.controlSize,
            height: metrics.controlSize
        )

        let availableSummaryWidth = max(
            bounds.width - metrics.leadingTextInset - metrics.textStatusSpacing - metrics.controlSize,
            0
        )
        let summaryWidth = measuredSummaryWidth(maxWidth: availableSummaryWidth, height: contentHeight)
        let statusX = max(0, min(
            metrics.leadingTextInset + summaryWidth + metrics.textStatusSpacing,
            bounds.width - metrics.controlSize
        ))
        summaryField.frame = NSRect(
            x: metrics.leadingTextInset,
            y: contentY + ((contentHeight - ceil(summaryField.fittingSize.height)) / 2),
            width: summaryWidth,
            height: ceil(summaryField.fittingSize.height)
        )
        statusView.frame = NSRect(
            x: statusX,
            y: contentY + ((contentHeight - metrics.controlSize) / 2),
            width: metrics.controlSize,
            height: metrics.controlSize
        )

        frame.size.height = measuredHeight(for: configuration)
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
        case .subAgent:
            return "person.crop.circle"
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

    func setDisclosureHoveredForTesting(_ hovered: Bool, animated: Bool = false) {
        setDisclosureHovered(hovered, animated: animated)
    }
}
#endif
