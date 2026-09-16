import AppKit

/// One keyboard-accessible destination per reviewer. Width is prepared before the shell measures
/// its stack, so wrapping never leaves the following transcript row at an obsolete offset.
@MainActor
final class AppKitReviewTeamReviewerRowView: AppKitHostToolWidgetBubbleView {
    enum FocusPresentation {
        case mouse, keyboard
    }

    let reviewerID: String

    /// Direct restoration after a sheet or rebuild must retain the opening interaction;
    /// Escape dismissing mouse-opened details is not keyboard navigation into this row.
    var focusPresentation: FocusPresentation = .mouse {
        didSet {
            guard focusPresentation != oldValue else { return }
            noteFocusRingMaskChanged()
            needsDisplay = true
        }
    }

    private let identity = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")
    private let monogram = AppKitFlippedDynamicColorView()
    private let monogramLabel = NSTextField(labelWithString: "")
    private let statusIcon = AppKitDynamicTintImageView()
    private let spinner = AppKitStatusIndicatorSpinner(lineWidth: 1.5)
    private let chevron = AppKitDynamicTintImageView()
    private let iconSize: CGFloat
    private let monogramSize: CGFloat
    private var layoutWidth: CGFloat = 0
    private var statusColumnWidth: CGFloat = 0

    init(
        member: ReviewWorkerConfiguration,
        model: String,
        role: String,
        status: ReviewTeamRunPresentation.ReviewerStatus,
        typography: TranscriptTypography
    ) {
        reviewerID = member.id
        iconSize = typography.size(for: .toolStatusIcon)
        monogramSize = max(22, typography.size(for: .caption) + 8)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isInteractive = true
        wantsLayer = true
        layer?.cornerRadius = AppCornerRadius.standard
        onHoverChanged = { [weak self] hovered in
            self?.setLayerFillColor(.secondaryLabelColor, alpha: hovered ? 0.08 : 0)
        }
        configureIdentity(model: model, role: role, typography: typography)
        configureMonogram(harness: member.harnessID, typography: typography)
        configureStatus(status, typography: typography)
        chevron.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: iconSize, weight: .medium)
        chevron.setDynamicContentTintColor(.tertiaryLabelColor)
        for child in [monogram, identity, statusLabel, statusIcon, spinner, chevron] {
            child.setAccessibilityElement(false)
            addSubview(child)
        }
        let description = [
            "\(role), requested model \(member.harnessID.capitalized) \(model), \(status.label)", status.detail
        ].compactMap { $0 }.joined(separator: ". ")
        toolTip = description + ". Show prompts and responses."
        setAccessibilityLabel(description)
        setAccessibilityHelp("Show this reviewer's prompts and responses.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var naturalWidth: CGFloat {
        monogramSize + 10 + ceil(identity.cell?.cellSize.width ?? 0)
            + 18 + max(preferredStatusWidth, statusColumnWidth) + iconSize + 10
    }

    var preferredStatusWidth: CGFloat {
        iconSize + 6 + ceil(statusLabel.cell?.cellSize.width ?? 0)
    }

    override var fittingSize: NSSize {
        NSSize(width: naturalWidth, height: rowLayout.height)
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: rowLayout.height)
    }

    func prepareLayout(width: CGFloat, statusWidth: CGFloat) {
        guard layoutWidth != width || statusColumnWidth != statusWidth else { return }
        layoutWidth = width
        statusColumnWidth = statusWidth
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let metrics = rowLayout
        identity.frame = metrics.identity
        monogram.frame = NSRect(x: 0, y: 3, width: monogramSize, height: monogramSize)
        let labelHeight = ceil(monogramLabel.fittingSize.height)
        monogramLabel.frame = NSRect(x: 0, y: (monogramSize - labelHeight) / 2, width: monogramSize, height: labelHeight)
        statusLabel.frame = metrics.status
        let symbolFrame = NSRect(
            x: metrics.status.minX - iconSize - 6,
            y: metrics.status.midY - iconSize / 2,
            width: iconSize, height: iconSize
        )
        statusIcon.frame = symbolFrame
        spinner.frame = symbolFrame
        chevron.frame = NSRect(x: max(0, layoutWidth - iconSize), y: 3 + (monogramSize - iconSize) / 2,
                              width: iconSize, height: iconSize)
    }

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        guard super.becomeFirstResponder() else { return false }
        if let direction = window?.keyViewSelectionDirection, direction != .directSelection {
            focusPresentation = .keyboard
        }
        return true
    }

    override func mouseDown(with event: NSEvent) {
        focusPresentation = .mouse
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        focusPresentation = .keyboard
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
            super.keyDown(with: event)
            return
        }
        switch event.keyCode {
        case 36, 49, 76:
            onActivate?()
        case 48:
            // NSView does not interpret Tab for a custom control; keep the native key-view
            // loop reachable so keyboard focus can leave the reviewer rows.
            if event.modifierFlags.contains(.shift) {
                window?.selectKeyView(preceding: self)
            } else {
                window?.selectKeyView(following: self)
            }
        default:
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        guard focusPresentation == .keyboard else { return }
        NSBezierPath(roundedRect: bounds, xRadius: AppCornerRadius.standard, yRadius: AppCornerRadius.standard).fill()
    }
}

private extension AppKitReviewTeamReviewerRowView {
    struct RowLayout {
        let identity: NSRect
        let status: NSRect
        let height: CGFloat
    }

    var rowLayout: RowLayout {
        let width = layoutWidth > 0 ? layoutWidth : naturalWidth
        let leading = monogramSize + 10
        let available = max(1, width - leading - iconSize - 10)
        let statusWidth = max(preferredStatusWidth, statusColumnWidth)
        let identityNaturalWidth = ceil(identity.cell?.cellSize.width ?? 0)
        let stacksStatus = available - statusWidth - 18 < min(identityNaturalWidth, 180)
        let identityWidth = stacksStatus ? available : max(1, available - statusWidth - 18)
        let identityHeight = textHeight(identity, width: identityWidth)
        let statusTextWidth = max(1, (stacksStatus ? available : statusWidth) - iconSize - 6)
        let statusHeight = textHeight(statusLabel, width: statusTextWidth)
        let firstHeight = max(monogramSize, identityHeight, stacksStatus ? 0 : statusHeight)
        let identityFrame = NSRect(x: leading, y: 3 + (firstHeight - identityHeight) / 2,
                                  width: identityWidth, height: identityHeight)
        let statusFrame = NSRect(
            x: stacksStatus ? leading + iconSize + 6 : width - iconSize - 10 - statusWidth + iconSize + 6,
            y: stacksStatus ? 3 + firstHeight + 3 : 3 + (firstHeight - statusHeight) / 2,
            width: statusTextWidth, height: statusHeight
        )
        return RowLayout(identity: identityFrame, status: statusFrame,
                         height: ceil(6 + firstHeight + (stacksStatus ? statusHeight + 3 : 0)))
    }

    func textHeight(_ field: NSTextField, width: CGFloat) -> CGFloat {
        // NSTextField reserves horizontal cell padding even for borderless labels. Measuring
        // only the attributed string fits a line that the cell then wraps and clips.
        ceil(field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 0)
    }

    func configureIdentity(model: String, role: String, typography: TranscriptTypography) {
        let text = NSMutableAttributedString(string: model, attributes: [
            .font: typography.nsFont(.caption, weight: .medium), .foregroundColor: NSColor.labelColor
        ])
        text.append(NSAttributedString(string: "  \(role)", attributes: [
            .font: typography.nsFont(.caption), .foregroundColor: NSColor.secondaryLabelColor
        ]))
        identity.attributedStringValue = text
        identity.lineBreakMode = .byWordWrapping
        identity.maximumNumberOfLines = 0
    }

    func configureMonogram(harness: String, typography: TranscriptTypography) {
        switch harness {
        case "codex": monogramLabel.stringValue = "Cx"
        case "claude": monogramLabel.stringValue = "Cl"
        default: monogramLabel.stringValue = String(harness.prefix(2)).uppercased()
        }
        monogramLabel.font = typography.nsFont(.caption, weight: .medium)
        monogramLabel.textColor = .secondaryLabelColor
        monogramLabel.alignment = .center
        monogramLabel.setAccessibilityElement(false)
        monogram.wantsLayer = true
        monogram.layer?.cornerRadius = AppCornerRadius.standard
        monogram.setLayerFillColor(.secondaryLabelColor, alpha: 0.09)
        monogram.addSubview(monogramLabel)
    }

    func configureStatus(_ status: ReviewTeamRunPresentation.ReviewerStatus, typography: TranscriptTypography) {
        statusLabel.attributedStringValue = NSAttributedString(string: status.label, attributes: [
            .font: typography.nsFont(.caption),
            .foregroundColor: status.failed ? NSColor.systemRed : NSColor.secondaryLabelColor
        ])
        statusLabel.lineBreakMode = .byWordWrapping
        statusLabel.maximumNumberOfLines = 0
        spinner.isHidden = status.visualState != .working
        statusIcon.isHidden = status.visualState == .working
        let symbol: String
        let color: NSColor
        switch status.visualState {
        case .working, .idle: (symbol, color) = ("circle", .tertiaryLabelColor)
        case .completed: (symbol, color) = ("checkmark.circle.fill", .systemGreen)
        case .failed: (symbol, color) = ("exclamationmark.circle.fill", .systemRed)
        }
        statusIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        statusIcon.symbolConfiguration = .init(pointSize: iconSize, weight: .regular)
        statusIcon.setDynamicContentTintColor(color)
    }
}
