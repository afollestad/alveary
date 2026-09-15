import AppKit

/// A vote stays one wrapping line until its reviewer-specific rationale is requested.
@MainActor
final class AppKitReviewProposalCompactVoteRowView: AppKitHostToolWidgetBubbleView {
    let reviewerID: String
    let isExpanded: Bool

    init(
        reviewer: PullRequestReviewVotePresentation.Reviewer,
        configuration: PullRequestReviewProposalRecord.Reviewer?,
        role: String,
        typography: TranscriptTypography,
        isExpanded: Bool
    ) {
        reviewerID = reviewer.id
        self.isExpanded = isExpanded
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        isInteractive = !reviewer.rationale.isEmpty
        wantsLayer = true
        layer?.cornerRadius = AppCornerRadius.standard
        onHoverChanged = { [weak self] hovered in
            self?.setLayerFillColor(.secondaryLabelColor, alpha: hovered ? 0.08 : 0)
        }
        configureContent(reviewer: reviewer, configuration: configuration, role: role, typography: typography)
        let action = isInteractive ? ". \(isExpanded ? "Hide" : "Show") rationale" : ""
        setAccessibilityElement(true)
        setAccessibilityRole(isInteractive ? .button : .group)
        setAccessibilityLabel(reviewer.accessibilityLabel + action)
        setAccessibilityValue(isInteractive ? (isExpanded ? "Expanded" : "Collapsed") : nil)
        let detail = [reviewer.accessibilityLabel, reviewer.rationale].filter { !$0.isEmpty }.joined(separator: ". ")
        setAccessibilityHelp(detail)
        toolTip = detail
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var acceptsFirstResponder: Bool { isInteractive }

    override func keyDown(with event: NSEvent) {
        if isInteractive, [36, 49, 76].contains(event.keyCode),
           event.modifierFlags.isDisjoint(with: [.command, .control, .option]) {
            onActivate?()
        } else {
            super.keyDown(with: event)
        }
    }

    override var focusRingMaskBounds: NSRect { bounds }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: AppCornerRadius.standard, yRadius: AppCornerRadius.standard).fill()
    }
}

private extension AppKitReviewProposalCompactVoteRowView {
    func configureContent(
        reviewer: PullRequestReviewVotePresentation.Reviewer,
        configuration: PullRequestReviewProposalRecord.Reviewer?,
        role: String,
        typography: TranscriptTypography
    ) {
        let label = AppKitTranscriptWidgetLabelFactory.label(
            "", level: .caption, color: .labelColor, typography: typography, wraps: true
        )
        let text = NSMutableAttributedString(string: modelLabel(configuration), attributes: [
            .font: typography.nsFont(.caption, weight: .medium), .foregroundColor: NSColor.labelColor
        ])
        text.append(NSAttributedString(string: "  \(role)  ·  ", attributes: [
            .font: typography.nsFont(.caption), .foregroundColor: NSColor.secondaryLabelColor
        ]))
        text.append(NSAttributedString(string: reviewer.status, attributes: [
            .font: typography.nsFont(.caption, weight: .medium), .foregroundColor: NSColor.secondaryLabelColor
        ]))
        label.attributedStringValue = text
        label.setAccessibilityElement(false)
        let content = NSStackView(views: [label])
        content.translatesAutoresizingMaskIntoConstraints = false
        content.orientation = .horizontal
        content.alignment = .centerY
        content.distribution = .fill
        content.spacing = 8
        if isInteractive { content.addArrangedSubview(disclosureChevron(size: typography.size(for: .toolStatusIcon))) }
        addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor),
            content.trailingAnchor.constraint(equalTo: trailingAnchor),
            content.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            content.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        ])
    }

    func disclosureChevron(size: CGFloat) -> NSView {
        let chevron = AppKitDynamicTintImageView()
        chevron.translatesAutoresizingMaskIntoConstraints = false
        chevron.image = NSImage(systemSymbolName: isExpanded ? "chevron.up" : "chevron.down", accessibilityDescription: nil)
        chevron.symbolConfiguration = .init(pointSize: size, weight: .medium)
        chevron.setDynamicContentTintColor(.tertiaryLabelColor)
        chevron.setAccessibilityElement(false)
        chevron.widthAnchor.constraint(equalToConstant: size).isActive = true
        chevron.heightAnchor.constraint(equalToConstant: size).isActive = true
        return chevron
    }

    /// Match only the saved exact catalog ID, so an old alias never claims a newer pinned model.
    func modelLabel(_ configuration: PullRequestReviewProposalRecord.Reviewer?) -> String {
        guard let configuration else { return "Model unavailable" }
        return ReviewTeamRunCardPresentation.modelLabel(
            harnessID: configuration.harnessID, modelOptionID: configuration.modelOptionID
        )
    }
}
