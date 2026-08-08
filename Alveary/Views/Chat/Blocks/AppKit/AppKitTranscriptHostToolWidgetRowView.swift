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
        /// Live review-confirmation state, with the diff preview and picked verdict.
        let reviewProposal: ReviewProposalWidgetState?
        let isProposalInteractive: Bool
        let isResolving: Bool
        /// The widget's target task has a run in flight; drives run-now's tense.
        let isTargetRunInFlight: Bool
        let errorMessage: String?
        let bubbleMaxWidth: CGFloat
        let typography: TranscriptTypography

        init(
            entry: HostToolWidgetEntry,
            proposalPresentation: ScheduledTaskProposalPresentation? = nil,
            reviewProposal: ReviewProposalWidgetState? = nil,
            isProposalInteractive: Bool = false,
            isResolving: Bool = false,
            isTargetRunInFlight: Bool = false,
            errorMessage: String? = nil,
            bubbleMaxWidth: CGFloat = .infinity,
            typography: TranscriptTypography = TranscriptTypography()
        ) {
            self.entry = entry
            self.proposalPresentation = proposalPresentation
            self.reviewProposal = reviewProposal
            self.isProposalInteractive = isProposalInteractive
            self.isResolving = isResolving
            self.isTargetRunInFlight = isTargetRunInFlight
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
    var onConfirmReviewProposal: ((String, PullRequestReviewEvent) -> Void)?
    var onRejectReviewProposal: ((String) -> Void)?
    var onSelectReviewVerdict: ((String, PullRequestReviewEvent) -> Void)?
    var onRemoveReviewProposalComment: ((String, Int) -> Void)?
    /// Fetches comment-author avatars. Kept off `Configuration`, which is `Equatable`: the loader
    /// is an actor, and it is app-lifetime constant rather than per-render input.
    var avatarLoader: GitHubAvatarLoader?
    /// Opens a link inside a review proposal's pending comment body.
    var onOpenMarkdownLink: ((URL) -> Void)?

    private let bubbleView = AppKitHostToolWidgetBubbleView()
    private let contentStack = NSStackView()
    private let headerStack = NSStackView()
    private let iconView = AppKitHostToolWidgetIconView()
    private let summaryField = NSTextField(labelWithString: "")
    private let disclosureSlot = AppKitHostToolWidgetDisclosureSlotView()
    private let detailField = NSTextField(labelWithString: "")
    private let proposalBody = AppKitScheduledTaskProposalWidgetView()
    private let reviewProposalBody = AppKitReviewProposalWidgetView()
    private let pullRequestListBody = AppKitPullRequestListWidgetView()
    private let reviewInstructionsBody = AppKitReviewInstructionsWidgetView()

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

        setupProposalBodies()
    }

    func setupProposalBodies() {
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

        setupReviewProposalBody()

        pullRequestListBody.translatesAutoresizingMaskIntoConstraints = false
        pullRequestListBody.onOpenPullRequest = { [weak self] identifier in
            self?.onOpenPullRequest?(identifier)
        }
        // Expanding the list adds rows below the fold, so the row has to republish its height.
        pullRequestListBody.onHeightInvalidated = { [weak self] in
            self?.measureAndPublishHeight(force: true)
        }
        contentStack.addFullWidthArrangedSubview(pullRequestListBody)

        reviewInstructionsBody.translatesAutoresizingMaskIntoConstraints = false
        // Revealing the instructions grows the card, so the row has to republish its height.
        reviewInstructionsBody.onHeightInvalidated = { [weak self] in
            self?.measureAndPublishHeight(force: true)
        }
        reviewInstructionsBody.onOpenMarkdownLink = { [weak self] url in
            self?.onOpenMarkdownLink?(url)
        }
        contentStack.addFullWidthArrangedSubview(reviewInstructionsBody)
    }

    /// Its own function so `setupProposalBodies` stays inside the shared function-length limit; the
    /// review proposal carries the most callbacks of any body here.
    func setupReviewProposalBody() {
        reviewProposalBody.translatesAutoresizingMaskIntoConstraints = false
        reviewProposalBody.onConfirm = { [weak self] proposalID, event in
            self?.onConfirmReviewProposal?(proposalID, event)
        }
        reviewProposalBody.onReject = { [weak self] proposalID in
            self?.onRejectReviewProposal?(proposalID)
        }
        reviewProposalBody.onSelectEvent = { [weak self] proposalID, event in
            self?.onSelectReviewVerdict?(proposalID, event)
        }
        reviewProposalBody.onRemoveComment = { [weak self] proposalID, index in
            self?.onRemoveReviewProposalComment?(proposalID, index)
        }
        reviewProposalBody.onOpenPullRequest = { [weak self] identifier in
            self?.onOpenPullRequest?(identifier)
        }
        // A comment card's markdown body grows when an inline image lands, and removing a comment
        // shrinks the card, which moves everything below it either way.
        reviewProposalBody.onHeightInvalidated = { [weak self] in
            self?.measureAndPublishHeight(force: true)
        }
        reviewProposalBody.onOpenMarkdownLink = { [weak self] url in
            self?.onOpenMarkdownLink?(url)
        }
        contentStack.addFullWidthArrangedSubview(reviewProposalBody)
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
    /// so the whole card takes the click; the review-instructions card is the one other pressable
    /// card, toggling its disclosure in place. Every other widget keeps its buttons and stays inert.
    func updateActivation(_ configuration: Configuration) {
        let togglesInstructions = Self.togglesReviewInstructions(configuration.entry)
        let isInteractive = configuration.entry.openableTarget != nil || togglesInstructions
        disclosureSlot.isHidden = !isInteractive
        disclosureSlot.configure(
            size: configuration.typography.size(for: .caption),
            capHeight: configuration.typography.nsFont(.toolSummary).capHeight
        )
        disclosureSlot.setExpanded(togglesInstructions && reviewInstructionsBody.isExpanded, animated: false)
        bubbleView.setAccessibilityLabel(
            [summaryField.stringValue, detailField.isHidden ? nil : detailField.stringValue]
                .compactMap { $0 }
                .joined(separator: ", ")
        )
        bubbleView.setAccessibilityValue(
            togglesInstructions ? (reviewInstructionsBody.isExpanded ? "Expanded" : "Collapsed") : nil
        )
        bubbleView.toolTip = togglesInstructions ? "Show or hide the review instructions" : nil
        bubbleView.isInteractive = isInteractive
    }

    /// The card is pressable exactly when it has instructions to reveal; a running or failed
    /// call has nothing behind the caret.
    static func togglesReviewInstructions(_ entry: HostToolWidgetEntry) -> Bool {
        guard case .pullRequestReviewInstructions(let content) = entry.content else {
            return false
        }
        return content.hasInstructions
    }

    func activateCard() {
        guard let configuration else {
            return
        }
        if Self.togglesReviewInstructions(configuration.entry) {
            toggleReviewInstructions()
            return
        }
        switch configuration.entry.openableTarget {
        case .pullRequest(let identifier):
            onOpenPullRequest?(identifier)
        case .thread(let conversationID):
            onOpenThread?(conversationID)
        case nil:
            break
        }
    }

    /// Expansion is body-local state, so the toggle updates the pieces configure would: the body's
    /// visibility, the caret's rotation, the accessibility value, and the row's measured height.
    func toggleReviewInstructions() {
        let expanded = reviewInstructionsBody.toggleExpansion()
        reviewInstructionsBody.isHidden = !expanded
        disclosureSlot.setExpanded(expanded, animated: true)
        bubbleView.setAccessibilityValue(expanded ? "Expanded" : "Collapsed")
        needsLayout = true
        // The card just changed size; the transcript measures rows from their content, so it has
        // to remeasure this one or the rows below sit at the old offsets.
        measureAndPublishHeight(force: true)
    }

    func updateHeader(_ configuration: Configuration) {
        let entry = configuration.entry
        let font = configuration.typography.nsFont(.toolSummary)
        summaryField.font = font
        summaryField.textColor = .labelColor
        summaryField.attributedStringValue = Self.summaryString(
            HostToolWidgetSummary.text(for: entry, isTargetRunInFlight: configuration.isTargetRunInFlight),
            emphasizing: HostToolWidgetSummary.emphasis(for: entry),
            font: font
        )

        // The detail line is author-written — a pull request title, a task name, a review body —
        // so it renders as markdown. Its fill is the muted wash, matching the already-secondary
        // text it sits on.
        let detail = HostToolWidgetSummary.detail(for: entry)
        let detailFont = configuration.typography.nsFont(.caption)
        detailField.font = detailFont
        detailField.attributedStringValue = AppKitMarkdownInlineString.attributedString(
            for: detail ?? "",
            baseFont: detailFont,
            foregroundColor: .secondaryLabelColor,
            inlineCodeFill: AppKitMarkdownInlineString.mutedInlineCodeFill(over: .secondaryLabelColor)
        )
        detailField.isHidden = detail == nil

        applyIcon(for: entry, typography: configuration.typography)
    }

    /// A pending review proposal names its pull request with GitHub's own octicon, and the
    /// review-instructions card wears the code-review octicon whenever it has not failed — the
    /// glyph names the activity. Every other state keeps the shell's status glyph, which is what
    /// carries the outcome.
    func applyIcon(for entry: HostToolWidgetEntry, typography: TranscriptTypography) {
        let size = typography.size(for: .toolIcon)
        iconView.summaryCapHeight = typography.nsFont(.toolSummary).capHeight
        if readsReviewInstructions(entry), let octicon = octicon(.codeReview16, size: size) {
            iconView.symbolConfiguration = nil
            iconView.image = octicon
            iconView.setDynamicContentTintColor(.secondaryLabelColor)
            return
        }
        if awaitsReviewDecision(entry), let octicon = pullRequestOcticon(size: size) {
            // The asset is artwork, not a symbol, so a stale symbol configuration would rescale it.
            iconView.symbolConfiguration = nil
            iconView.image = octicon
            iconView.setDynamicContentTintColor(.secondaryLabelColor)
            return
        }
        let symbol = statusSymbol(for: entry)
        iconView.image = NSImage(systemSymbolName: symbol.name, accessibilityDescription: nil)
        iconView.symbolConfiguration = .init(pointSize: size, weight: .regular)
        iconView.setDynamicContentTintColor(symbol.tint)
    }

    /// Its own function so `updateBody` stays inside the shared function-length limit; the
    /// proposal is the one body here with live confirmation state to thread through.
    func updateReviewProposalBody(
        _ content: PullRequestReviewProposalWidgetContent,
        configuration: Configuration
    ) {
        let state = configuration.reviewProposal ?? ReviewProposalWidgetState()
        reviewProposalBody.avatarLoader = avatarLoader
        reviewProposalBody.configure(
            .init(
                content: content,
                presentation: state.presentation,
                preview: state.preview,
                selectedEvent: state.selectedEvent,
                canSubmit: state.canSubmit,
                isInteractive: configuration.isProposalInteractive,
                isSubmitting: state.isSubmitting,
                outcome: configuration.entry.outcome,
                errorMessage: state.errorMessage ?? configuration.errorMessage,
                typography: configuration.typography
            )
        )
        reviewProposalBody.isHidden = !reviewProposalBody.hasContent
    }

    func updateBody(_ configuration: Configuration) {
        reviewProposalBody.isHidden = true
        pullRequestListBody.isHidden = true
        reviewInstructionsBody.isHidden = true
        switch configuration.entry.content {
        case .pullRequestLink, .threadAction:
            // The header and detail lines say everything these cards have to say.
            proposalBody.isHidden = true
        case .pullRequestReviewInstructions(let content):
            proposalBody.isHidden = true
            reviewInstructionsBody.configure(
                .init(content: content, typography: configuration.typography)
            )
            // Collapsed hides the whole container, not just the markdown — a visible empty
            // body would still cost the content stack's row spacing under the header.
            reviewInstructionsBody.isHidden = !(reviewInstructionsBody.hasContent && reviewInstructionsBody.isExpanded)
        case .pullRequestList(let content):
            proposalBody.isHidden = true
            pullRequestListBody.configure(
                .init(content: content, typography: configuration.typography)
            )
            pullRequestListBody.isHidden = !pullRequestListBody.hasContent
        case .pullRequestReviewProposal(let content):
            proposalBody.isHidden = true
            updateReviewProposalBody(content, configuration: configuration)
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
        let reviewWidth = reviewProposalBody.isHidden ? 0 : reviewProposalBody.naturalWidth
        let listWidth = pullRequestListBody.isHidden ? 0 : pullRequestListBody.naturalWidth
        let instructionsWidth = reviewInstructionsBody.isHidden ? 0 : reviewInstructionsBody.naturalWidth
        return ceil(max(headerWidth, detailWidth, bodyWidth, reviewWidth, listWidth, instructionsWidth))
            + (chatBlockPadding * 2)
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
