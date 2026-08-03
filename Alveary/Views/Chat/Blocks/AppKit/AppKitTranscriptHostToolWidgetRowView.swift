import AppKit

/// Transcript block for an Alveary host MCP tool.
///
/// The shell owns chrome, the one-line status summary, and measurement; each feature
/// contributes a body view selected by `HostToolWidgetContent`, so a new host tool
/// adds a case here plus its own body view and nothing else in the pipeline.
@MainActor
final class AppKitTranscriptHostToolWidgetRowView: NSView {
    struct Configuration: Equatable {
        let entry: HostToolWidgetEntry
        /// Live confirmation state; `nil` once the proposal is resolved or gone.
        let proposalPresentation: ScheduledTaskProposalPresentation?
        let isProposalInteractive: Bool
        let isResolving: Bool
        /// The widget's target task has a run in flight; drives run-now's tense.
        let isTargetRunInFlight: Bool
        /// This card's pull request is being fetched before its pane can open.
        let isOpeningPullRequest: Bool
        let errorMessage: String?
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            entry: HostToolWidgetEntry,
            proposalPresentation: ScheduledTaskProposalPresentation? = nil,
            isProposalInteractive: Bool = false,
            isResolving: Bool = false,
            isTargetRunInFlight: Bool = false,
            isOpeningPullRequest: Bool = false,
            errorMessage: String? = nil,
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.entry = entry
            self.proposalPresentation = proposalPresentation
            self.isProposalInteractive = isProposalInteractive
            self.isResolving = isResolving
            self.isTargetRunInFlight = isTargetRunInFlight
            self.isOpeningPullRequest = isOpeningPullRequest
            self.errorMessage = errorMessage
            self.bubbleMaxWidth = bubbleMaxWidth
            self.typography = typography
        }
    }

    var onHeightInvalidated: (() -> Void)?
    var onConfirmScheduledProposal: ((String) -> Void)?
    var onReviewScheduledProposal: ((String) -> Void)?
    var onRejectScheduledProposal: ((String) -> Void)?
    var onOpenScheduledTask: ((String?) -> Void)?
    var onOpenPullRequest: ((PullRequestIdentifier) -> Void)?
    var onOpenThread: ((String) -> Void)?

    private let bubbleView = AppKitHostToolWidgetBubbleView()
    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let iconView = AppKitDynamicTintImageView()
    private let summaryField = NSTextField(labelWithString: "")
    private let disclosureSlot = AppKitHostToolWidgetDisclosureSlotView()
    private let detailField = NSTextField(labelWithString: "")
    private let proposalBody = AppKitScheduledTaskProposalWidgetView()

    private var configuration: Configuration?
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
        NSSize(width: NSView.noIntrinsicMetric, height: max(lastMeasuredHeight, 0))
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        let widthChanged = self.configuration?.bubbleMaxWidth != configuration.bubbleMaxWidth
        self.configuration = configuration
        updateHeader(configuration)
        updateBody(configuration)
        updateActivation(configuration)
        updateBubbleAppearance()
        needsLayout = true
        measureAndPublishHeight(force: widthChanged)
    }

    override func layout() {
        // Measuring re-lays out `bubbleView`'s own subtree, not this row, so it cannot
        // re-enter here; `publishHeight` no-ops unless the fitted height actually moved.
        measureAndPublishHeight(force: false)
        super.layout()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBubbleAppearance()
    }

}

private extension AppKitTranscriptHostToolWidgetRowView {
    func setup() {
        translatesAutoresizingMaskIntoConstraints = false
        bubbleView.wantsLayer = true
        bubbleView.layer?.cornerRadius = chatBlockCornerRadius
        bubbleView.onActivate = { [weak self] in
            self?.activateCard()
        }
        bubbleView.onHoverChanged = { [weak self] _ in
            self?.updateBubbleAppearance()
        }
        addSubview(bubbleView)

        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        bubbleView.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: bubbleView.leadingAnchor, constant: chatBlockPadding),
            contentStack.trailingAnchor.constraint(equalTo: bubbleView.trailingAnchor, constant: -chatBlockPadding),
            contentStack.topAnchor.constraint(equalTo: bubbleView.topAnchor, constant: chatVerticalPadding)
        ])

        setupHeader()

        detailField.translatesAutoresizingMaskIntoConstraints = false
        detailField.lineBreakMode = .byTruncatingTail
        detailField.maximumNumberOfLines = 1
        contentStack.addFullWidthArrangedSubview(detailField)

        proposalBody.translatesAutoresizingMaskIntoConstraints = false
        proposalBody.onConfirm = { [weak self] proposalID in
            self?.onConfirmScheduledProposal?(proposalID)
        }
        proposalBody.onReview = { [weak self] proposalID in
            self?.onReviewScheduledProposal?(proposalID)
        }
        proposalBody.onReject = { [weak self] proposalID in
            self?.onRejectScheduledProposal?(proposalID)
        }
        proposalBody.onOpenScheduledTask = { [weak self] definitionID in
            self?.onOpenScheduledTask?(definitionID)
        }
        contentStack.addFullWidthArrangedSubview(proposalBody)
    }

    func setupHeader() {
        headerStack.translatesAutoresizingMaskIntoConstraints = false
        headerStack.orientation = .horizontal
        headerStack.alignment = .firstBaseline
        headerStack.spacing = 8
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.setContentHuggingPriority(.required, for: .horizontal)
        // The glyph restates what the summary line already says, so it stays decorative.
        iconView.setAccessibilityElement(false)
        summaryField.translatesAutoresizingMaskIntoConstraints = false
        summaryField.lineBreakMode = .byWordWrapping
        summaryField.maximumNumberOfLines = 0
        summaryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        disclosureSlot.setContentHuggingPriority(.required, for: .horizontal)
        disclosureSlot.isHidden = true
        headerStack.addArrangedSubview(iconView)
        headerStack.addArrangedSubview(summaryField)
        headerStack.addArrangedSubview(disclosureSlot)
        contentStack.addFullWidthArrangedSubview(headerStack)
    }

    /// A card that names something openable — a pull request, a thread — is itself the control,
    /// so the whole card takes the click; every other widget keeps its buttons and stays inert.
    func updateActivation(_ configuration: Configuration) {
        let isInteractive = configuration.entry.openableTarget != nil
        disclosureSlot.isHidden = !isInteractive
        disclosureSlot.configure(
            size: configuration.typography.size(for: .caption),
            capHeight: configuration.typography.nsFont(.toolSummary).capHeight,
            // Only a pull request can keep the user waiting: opening one the thread no longer
            // links costs a GitHub round trip, so the chevron becomes a spinner rather than
            // sitting there looking like the click missed. Selecting a thread is local.
            isWaiting: isInteractive && configuration.isOpeningPullRequest
        )
        bubbleView.setAccessibilityLabel(
            [summaryField.stringValue, detailField.isHidden ? nil : detailField.stringValue]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        bubbleView.isInteractive = isInteractive
    }

    func activateCard() {
        switch configuration?.entry.openableTarget {
        case .pullRequest(let identifier):
            onOpenPullRequest?(identifier)
        case .thread(let conversationID):
            onOpenThread?(conversationID)
        case nil:
            break
        }
    }

    func updateHeader(_ configuration: Configuration) {
        let entry = configuration.entry
        summaryField.font = configuration.typography.nsFont(.toolSummary)
        summaryField.textColor = .labelColor
        summaryField.stringValue = HostToolWidgetSummary.text(
            for: entry,
            isTargetRunInFlight: configuration.isTargetRunInFlight
        )

        let detail = HostToolWidgetSummary.detail(for: entry)
        detailField.font = configuration.typography.nsFont(.caption)
        detailField.textColor = .secondaryLabelColor
        detailField.stringValue = detail ?? ""
        detailField.isHidden = detail == nil

        let symbol = statusSymbol(for: entry)
        iconView.image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(
            pointSize: configuration.typography.size(for: .toolIcon),
            weight: .regular
        )
        iconView.setDynamicContentTintColor(symbol.tint)
    }

    func statusSymbol(for entry: HostToolWidgetEntry) -> (name: String, tint: NSColor) {
        if entry.isError {
            return ("exclamationmark.triangle", .systemRed)
        }
        switch entry.outcome {
        case .confirmed:
            return ("checkmark.circle", .systemGreen)
        case .rejected:
            return ("xmark.circle", .secondaryLabelColor)
        case nil:
            return entry.isSettledWithoutDecision
                ? ("checkmark.circle", .systemGreen)
                : ("clock", .secondaryLabelColor)
        }
    }

    func updateBody(_ configuration: Configuration) {
        switch configuration.entry.content {
        case .pullRequestLink, .threadAction:
            // The header and detail lines say everything these cards have to say.
            proposalBody.isHidden = true
        case .scheduledTaskProposal(let content):
            proposalBody.configure(
                .init(
                    content: content,
                    presentation: configuration.proposalPresentation,
                    isInteractive: configuration.isProposalInteractive,
                    scheduledTaskID: configuration.entry.resolvedScheduledTaskID,
                    isResolving: configuration.isResolving,
                    outcome: configuration.entry.outcome,
                    errorMessage: configuration.errorMessage,
                    typography: configuration.typography
                )
            )
            proposalBody.isHidden = !proposalBody.hasContent
        }
    }

    func updateBubbleAppearance() {
        bubbleView.setLayerFillColor(.secondaryLabelColor, alpha: bubbleView.isHovered ? 0.11 : 0.06)
    }

    static let minimumBubbleWidth: CGFloat = 220

    /// The card hugs its content and only caps at the transcript's bubble width, matching
    /// how approval blocks size themselves.
    func bubbleWidth(for configuration: Configuration) -> CGFloat {
        let cap = configuration.bubbleMaxWidth.isFinite
            ? min(configuration.bubbleMaxWidth, bounds.width > 0 ? bounds.width : configuration.bubbleMaxWidth)
            : max(bounds.width, 0)
        guard cap > 0 else {
            return 0
        }
        return max(min(naturalBubbleWidth(), cap), min(Self.minimumBubbleWidth, cap))
    }

    func naturalBubbleWidth() -> CGFloat {
        let disclosureWidth = disclosureSlot.isHidden
            ? 0
            : disclosureSlot.intrinsicContentSize.width + headerStack.spacing
        let headerWidth = transcriptToolIconFrameSize + headerStack.spacing
            + ceil(summaryField.attributedStringValue.size().width) + disclosureWidth
        let detailWidth = detailField.isHidden ? 0 : ceil(detailField.attributedStringValue.size().width)
        let bodyWidth = proposalBody.isHidden ? 0 : proposalBody.naturalWidth
        return ceil(max(headerWidth, detailWidth, bodyWidth)) + (chatBlockPadding * 2)
    }

    func measureAndPublishHeight(force: Bool) {
        guard let configuration else {
            return
        }
        let width = bubbleWidth(for: configuration)
        guard width > 0 else {
            return
        }
        bubbleView.frame = NSRect(x: 0, y: 0, width: width, height: max(lastMeasuredHeight, 1))
        bubbleView.layoutSubtreeIfNeeded()
        let height = ceil(contentStack.frame.maxY + chatVerticalPadding)
        bubbleView.frame.size.height = height
        publishHeight(height, force: force)
    }

    func publishHeight(_ height: CGFloat, force: Bool) {
        guard force || abs(height - lastMeasuredHeight) > 0.5 else {
            return
        }
        lastMeasuredHeight = height
        invalidateIntrinsicContentSize()
        onHeightInvalidated?()
    }
}
