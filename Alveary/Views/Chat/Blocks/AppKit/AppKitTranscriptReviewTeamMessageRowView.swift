@preconcurrency import AppKit

/// One collective reviewer's status update: a reviewer header above a left-side bubble that opens
/// that reviewer's Run details, or the run's overview for a team message.
@MainActor
final class AppKitTranscriptReviewTeamMessageRowView: NSView {
    struct Configuration: Equatable {
        let message: ReviewTeamStatusMessage
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography
    }

    var onHeightInvalidated: (() -> Void)?
    /// Kept off `Configuration`: the run moves with every reviewer's progress, so comparing it would
    /// reconfigure each of its messages whenever any one of them changed.
    var run: ReviewTeamRun?

    private let monogram = AppKitReviewTeamMonogramView()
    private let header = NSTextField(labelWithString: "")
    private let bubble = AppKitKeyboardFocusableBubbleView()
    private let spinner = AppKitStatusIndicatorSpinner(lineWidth: 1.5)
    private let label = NSTextField(labelWithString: "")
    private var configuration: Configuration?
    private var lastMeasuredHeight: CGFloat = -1

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        header.lineBreakMode = .byTruncatingTail
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = chatBubbleCornerRadius
        bubble.isInteractive = true
        bubble.onHoverChanged = { [weak self] hovered in self?.updateFill(hovered: hovered) }
        bubble.onActivate = { [weak self] in self?.showDetails() }
        for child in [monogram, header, label, spinner] as [NSView] {
            child.setAccessibilityElement(false)
        }
        addSubview(monogram)
        addSubview(header)
        addSubview(bubble)
        bubble.addSubview(spinner)
        bubble.addSubview(label)
        updateFill(hovered: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: metrics(width: bounds.width).height)
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        let message = configuration.message
        let typography = configuration.typography
        let name: String
        let role: String?
        switch message.author {
        case .reviewer(let member, let reviewerRole):
            monogram.configure(harness: member.harnessID, typography: typography)
            name = ReviewTeamRunCardPresentation.modelLabel(harnessID: member.harnessID, modelOptionID: member.modelOptionID)
            role = reviewerRole
        case .team:
            monogram.configure(symbolName: "person.3", typography: typography)
            name = "Review team"
            role = nil
        }
        let identity = NSMutableAttributedString(string: name, attributes: [
            .font: typography.nsFont(.caption, weight: .semibold), .foregroundColor: NSColor.labelColor
        ])
        if let role {
            identity.append(NSAttributedString(string: "  \(role)", attributes: [
                .font: typography.nsFont(.caption), .foregroundColor: NSColor.secondaryLabelColor
            ]))
        }
        header.attributedStringValue = identity
        label.attributedStringValue = NSAttributedString(string: message.text, attributes: [
            .font: typography.nsFont(.body),
            .foregroundColor: message.state == .failed ? NSColor.systemRed : NSColor.labelColor
        ])
        spinner.isHidden = message.state != .working
        let help = message.reviewerID == nil ? "Show the review's run details." : "Show this reviewer's prompts and responses."
        bubble.setAccessibilityLabel("\([name, role].compactMap { $0 }.joined(separator: ", ")): \(message.text)")
        bubble.setAccessibilityHelp(help)
        bubble.toolTip = help
        needsLayout = true
        invalidateHeight(force: true)
    }

    override func layout() {
        super.layout()
        let metrics = metrics(width: bounds.width)
        monogram.frame = metrics.monogram
        header.frame = metrics.header
        bubble.frame = metrics.bubble
        spinner.frame = metrics.spinner
        label.frame = metrics.label
        invalidateHeight(force: false)
    }
}

private extension AppKitTranscriptReviewTeamMessageRowView {
    struct Metrics {
        let monogram: NSRect
        let header: NSRect
        let bubble: NSRect
        let spinner: NSRect
        let label: NSRect

        var height: CGFloat { ceil(bubble.maxY) }
    }

    /// The bubble hugs its text up to the transcript's bubble cap, indented under the reviewer's name.
    func metrics(width: CGFloat) -> Metrics {
        let typography = configuration?.typography ?? TranscriptTypography()
        let monogramSize = max(22, typography.size(for: .caption) + 8)
        let indent = monogramSize + 8
        let cap = configuration.map { $0.bubbleMaxWidth.isFinite ? min($0.bubbleMaxWidth, width) : width } ?? width
        let headerHeight = ceil(header.fittingSize.height)
        let headerFrame = NSRect(
            x: indent, y: (monogramSize - headerHeight) / 2,
            width: max(0, min(ceil(header.fittingSize.width), width - indent)), height: headerHeight
        )
        let iconSize = typography.size(for: .toolStatusIcon)
        let textX = chatBubbleHorizontalPadding + (spinner.isHidden ? 0 : iconSize + 6)
        let available = max(1, cap - indent - textX - chatBubbleHorizontalPadding)
        let textWidth = min(ceil(label.cell?.cellSize.width ?? 0), available)
        let textHeight = ceil(label.cell?.cellSize(
            forBounds: NSRect(x: 0, y: 0, width: textWidth, height: .greatestFiniteMagnitude)
        ).height ?? 0)
        let bubbleFrame = NSRect(
            x: indent, y: monogramSize + 4,
            width: textX + textWidth + chatBubbleHorizontalPadding, height: textHeight + chatBubbleVerticalPadding * 2
        )
        let firstLine = ceil(NSLayoutManager().defaultLineHeight(for: typography.nsFont(.body)))
        return Metrics(
            monogram: NSRect(x: 0, y: 0, width: monogramSize, height: monogramSize),
            header: headerFrame,
            bubble: bubbleFrame,
            spinner: NSRect(
                x: chatBubbleHorizontalPadding, y: chatBubbleVerticalPadding + (firstLine - iconSize) / 2,
                width: iconSize, height: iconSize
            ),
            label: NSRect(x: textX, y: chatBubbleVerticalPadding, width: textWidth, height: textHeight)
        )
    }

    func updateFill(hovered: Bool) {
        bubble.setLayerFillColor(.secondaryLabelColor, alpha: hovered ? 0.14 : 0.08)
    }

    func showDetails() {
        guard let run else { return }
        AppKitReviewTeamRunWidgetView.requestDetails(for: run, reviewerID: configuration?.message.reviewerID, sender: self)
    }

    func invalidateHeight(force: Bool) {
        let height = metrics(width: bounds.width).height
        guard force || abs(height - lastMeasuredHeight) > 0.5 else { return }
        lastMeasuredHeight = height
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }
}
