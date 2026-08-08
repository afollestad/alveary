import AppKit

/// A comment card's vertical neighbourhood: the tints its two bands continue, mirroring
/// `DiffCommentRowWash` on the SwiftUI side — the anchored line's above the card, the following
/// line's below — and whether anything follows it at all.
struct AppKitReviewProposalCommentWash: Equatable {
    let top: DiffCodeHighlighting.LineKind
    let bottom: DiffCodeHighlighting.LineKind
    /// Nothing follows, so the card's lower band ends at the diff block's own border rather than
    /// at another line. It takes the wider outset for that; see `trailingVerticalOutset`.
    let isTrailing: Bool

    init(top: DiffCodeHighlighting.LineKind, bottom: DiffCodeHighlighting.LineKind, isTrailing: Bool = false) {
        self.top = top
        self.bottom = bottom
        self.isTrailing = isTrailing
    }
}

/// A pending review comment as a card floating on the diff, mirroring the Changes tab's treatment.
///
/// The row draws two wash bands behind the card — the anchored line's tint above, the following
/// line's below — so the neighboring diff colors pass around it instead of stopping at a full-width
/// backdrop band. That is why the builder hands this view the *next* row's kind.
///
/// Its interior mirrors `DiffCommentThreadRow.commentView`: the avatar/author/badges row over a
/// markdown-rendered body. No reactions, no menu, no reply footer, no composer — every one of those
/// posts to GitHub, and nothing on this card may reach GitHub before the user confirms the review.
/// The trailing Remove is the one exception that proves the rule: it drops a staged comment from the
/// stored envelope, which is local by construction.
@MainActor
final class AppKitReviewProposalCommentCardView: NSView {
    /// Matches `DiffCommentCardChrome`: the card is inset from the row so the code surface shows
    /// around it and it reads as floating rather than as a band.
    static let horizontalOutset: CGFloat = 8
    static let verticalOutset: CGFloat = 4
    /// The last card in the preview has the block's border under it instead of another line, and at
    /// `verticalOutset` it crowds that border and its own shadow clips against it.
    static let trailingVerticalOutset: CGFloat = 10
    /// `DiffCommentCardInteriorPadding`; the wider trailing edge matches the Overview timeline cards.
    static let interiorPadding: CGFloat = 10
    static let interiorTrailingPadding: CGFloat = 12
    /// `DiffCommentCardChrome`'s own radius, deliberately not `AppCornerRadius.standard`.
    static let cornerRadius: CGFloat = 10

    /// The markdown body can change height after an inline image loads, so the card has to be able
    /// to tell the transcript its row grew.
    var onHeightInvalidated: (() -> Void)?
    /// A comment body is real markdown, so its links have to open like every other transcript link.
    var onOpenLink: ((URL) -> Void)? {
        didSet {
            bodyView.onOpenLink = onOpenLink
        }
    }
    /// Drops this card's staged comment from the review, by its position in the stored envelope.
    /// Set once when the pool creates the card; the index travels with each `configure`.
    var onRemove: ((Int) -> Void)?
    /// Opens this comment in the pull request pane, scrolled to the line it annotates. Set once
    /// when the pool creates the card; the anchor travels with each `configure`, for the same
    /// reason the index does.
    var onJump: ((DiffCommentAnchor) -> Void)?

    /// A transparent container: the card's fill, border, and shadow are drawn in `draw(_:)`, not
    /// backed by a `CALayer`. Two reasons — `AppKitDynamicColorView` rewrites `layer.borderColor`
    /// from its own provider on every window/appearance change, and a nil provider leaves
    /// `CALayer`'s opaque-black default; and a layer shadow is clipped by the transcript's
    /// clip-to-bounds row containers, so the elevation never rendered.
    private let card = AppKitFlippedContainerView()
    private let contentStack = NSStackView()
    private let authorRow = NSStackView()
    private let avatarView = AppKitPullRequestAvatarView()
    private let authorField = NSTextField(labelWithString: "")
    private let botBadge = AppKitPullRequestCommentBadgeView()
    private let pendingBadge = AppKitPullRequestCommentBadgeView()
    private let removeButton = AppKitReviewProposalCommentRemoveButton()
    private let jumpButton = AppKitReviewProposalCommentJumpButton()
    private let bodyView = AppKitMarkdownView(document: AppMarkdownDocument(content: AttributedString()))
    private var metrics = AppKitDiffCodeBlockMetrics.empty
    private var wash = AppKitReviewProposalCommentWash(top: .context, bottom: .context)
    /// The configured comment's position in the review's stored `comments` array; nil for a comment
    /// that lives on GitHub, which this card cannot remove.
    private var proposedIndex: Int?
    /// The configured comment's diff anchor, re-captured on every `configure` because these views
    /// are pooled — a stale one would jump to the previous comment's line.
    private var jumpAnchor: DiffCommentAnchor?
    /// Held because the outset widens for the preview's last card, and these views are pooled.
    private var cardBottomConstraint: NSLayoutConstraint?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        setupCard()
        setupContent()
        bodyView.onHeightInvalidated = { [weak self] in
            self?.onHeightInvalidated?()
        }
        // The button owns the arm/confirm step; this fires only on the confirming press.
        removeButton.onConfirm = { [weak self] in
            guard let self, let proposedIndex else {
                return
            }
            onRemove?(proposedIndex)
        }
        jumpButton.onJump = { [weak self] in
            guard let self, let jumpAnchor else {
                return
            }
            onJump?(jumpAnchor)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    func configure(
        comment: DiffLineComment,
        anchor: DiffCommentAnchor,
        wash: AppKitReviewProposalCommentWash,
        metrics: AppKitDiffCodeBlockMetrics,
        context: AppKitReviewProposalCommentContext
    ) {
        self.metrics = metrics
        self.wash = wash
        proposedIndex = comment.proposedIndex
        jumpAnchor = anchor
        cardBottomConstraint?.constant = -(wash.isTrailing ? Self.trailingVerticalOutset : Self.verticalOutset)
        let captionSize = context.typography.size(for: .caption)
        avatarView.configure(login: comment.author, url: comment.avatarURL, loader: context.avatarLoader)
        authorField.font = .systemFont(ofSize: captionSize, weight: .medium)
        authorField.stringValue = comment.author
        botBadge.isHidden = !comment.isBot
        botBadge.configure(title: "Bot", style: .outlined, fontSize: captionSize)
        botBadge.setAccessibilityLabel("Bot account")
        // "Proposed" marks a comment staged in the review proposal, existing only in Alveary;
        // "Pending" keeps meaning the user's own server-side draft. Same tint — both are
        // unpublished until the review is submitted.
        pendingBadge.isHidden = !(comment.isPending || comment.isProposed)
        pendingBadge.configure(
            title: comment.isProposed ? "Proposed" : "Pending",
            style: .tinted(AppKitPullRequestCommentBadgeView.pendingTint),
            fontSize: captionSize
        )
        // Only a staged comment can be removed, and only while the card can still act on it — a
        // submission in flight is already publishing what it was handed.
        removeButton.isHidden = !(context.allowsRemoval && comment.isProposed)
        removeButton.configure(fontSize: captionSize)
        // Only a staged comment jumps: a `Pending` one already lives on GitHub and the pane
        // renders it from the detail, with no proposal to attach to.
        jumpButton.isHidden = !(context.allowsJumping && comment.isProposed)
        jumpButton.configure(fontSize: captionSize)
        configureBody(markdown: comment.bodyMarkdown, typography: context.typography)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel("Comments on line \(anchor.line) of \(anchor.path)")
        needsDisplay = true
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    /// The wash bands first, then the card over them. Subviews draw after this, so the author row
    /// and body land on top of the fill.
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let midY = (bounds.height / 2).rounded()
        drawBand(kind: wash.top, in: NSRect(x: 0, y: 0, width: bounds.width, height: midY))
        drawBand(
            kind: wash.bottom,
            in: NSRect(x: 0, y: midY, width: bounds.width, height: bounds.height - midY)
        )
        AppKitDiffGutterPainter.drawSeparator(in: bounds, metrics: metrics)
        drawCard()
    }
}

/// A flipped, undrawn container. Only exists so the card's interior can be laid out against one
/// rect while the rect itself is painted by the row.
final class AppKitFlippedContainerView: NSView {
    override var isFlipped: Bool {
        true
    }
}

/// What a comment card needs beyond the comment itself: transcript fonts, the loader its avatar
/// fetches through, and whether the review can still be edited. The loader is absent in snapshots
/// and previews, which is what makes the card fall back to the author's initial.
struct AppKitReviewProposalCommentContext {
    let typography: TranscriptTypography
    let avatarLoader: GitHubAvatarLoader?
    /// False once a submission is in flight, which is the only interactive state where the review's
    /// staged comments are no longer the user's to change.
    let allowsRemoval: Bool
    /// False where there is nothing to jump to — snapshots and previews, and a card rendered in a
    /// conversation that did not open the proposal, which is read-only.
    let allowsJumping: Bool

    init(
        typography: TranscriptTypography,
        avatarLoader: GitHubAvatarLoader? = nil,
        allowsRemoval: Bool = false,
        allowsJumping: Bool = false
    ) {
        self.typography = typography
        self.avatarLoader = avatarLoader
        self.allowsRemoval = allowsRemoval
        self.allowsJumping = allowsJumping
    }
}

private extension AppKitReviewProposalCommentCardView {
    func setupCard() {
        card.translatesAutoresizingMaskIntoConstraints = false
        addSubview(card)
        let bottom = card.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -Self.verticalOutset)
        cardBottomConstraint = bottom
        NSLayoutConstraint.activate([
            card.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalOutset),
            card.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalOutset),
            card.topAnchor.constraint(equalTo: topAnchor, constant: Self.verticalOutset),
            bottom
        ])
    }

    func setupContent() {
        setupAuthorRow()
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        // `DiffCommentThreadRow.commentView`'s spacing between the author row and the body.
        contentStack.spacing = 8
        contentStack.addFullWidthArrangedSubview(authorRow)
        contentStack.addFullWidthArrangedSubview(bodyView)
        card.addSubview(contentStack)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: Self.interiorPadding),
            contentStack.trailingAnchor.constraint(
                equalTo: card.trailingAnchor,
                constant: -Self.interiorTrailingPadding
            ),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: Self.interiorPadding),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -Self.interiorPadding)
        ])
    }

    func setupAuthorRow() {
        authorRow.translatesAutoresizingMaskIntoConstraints = false
        authorRow.orientation = .horizontal
        authorRow.alignment = .centerY
        // `PullRequestCommentAuthorRow`'s spacing.
        authorRow.spacing = 6
        authorField.translatesAutoresizingMaskIntoConstraints = false
        authorField.textColor = .secondaryLabelColor
        authorField.lineBreakMode = .byTruncatingTail
        authorField.maximumNumberOfLines = 1
        authorRow.addArrangedSubview(avatarView)
        authorRow.addArrangedSubview(authorField)
        authorRow.addArrangedSubview(botBadge)
        authorRow.addArrangedSubview(pendingBadge)
        // The badges keep their intrinsic width; the author name is what yields on a narrow card.
        authorField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        for view in [avatarView, botBadge, pendingBadge, jumpButton, removeButton] {
            view.setContentHuggingPriority(.required, for: .horizontal)
            view.setContentCompressionResistancePriority(.required, for: .horizontal)
        }
        authorRow.addArrangedSubview(NSView())
        // After the flexible spacer, so they sit at the card's trailing edge — where the pane puts
        // its three-dot menu on this same card shape. Jump leads Remove: navigating is the
        // ordinary action, and the destructive one stays furthest from the pointer's path.
        authorRow.addArrangedSubview(jumpButton)
        authorRow.addArrangedSubview(removeButton)
    }

    func configureBody(markdown: String, typography: TranscriptTypography) {
        let document = AppMarkdownDocumentCache.document(
            markdown: markdown,
            context: AppMarkdownDocumentCacheContext(
                baseURL: nil,
                inlineCodeStyle: .standard,
                composerChipMode: .none,
                taskStateScope: nil
            )
        ) {
            AppMarkdownParser().documentPreservingSource(for: markdown)
        }
        bodyView.configure(
            document: document,
            inlineCodeStyle: .standard,
            typography: Self.bodyTypography(typography)
        )
    }

    /// Scaled down from `TranscriptTypography.appKitMarkdownTypography`, which renders at the full
    /// chat body size. A comment annotates caption-sized diff code, and at body size it dwarfed the
    /// lines it refers to; one notch above the author row keeps the pane's own body-over-author
    /// relationship without outgrowing the diff.
    static func bodyTypography(_ typography: TranscriptTypography) -> AppKitMarkdownTypography {
        AppKitMarkdownTypography(
            title1: typography.nsFont(.headline, weight: .semibold),
            title2: typography.nsFont(.headline, weight: .semibold),
            headline: typography.nsFont(.body, weight: .semibold),
            subheadline: typography.nsFont(.toolSummary, weight: .semibold),
            body: typography.nsFont(.toolSummary),
            codeBlock: typography.inlineToolCodeNSFont,
            inlineCode: typography.inlineToolCodeNSFont
        )
    }

    /// `DiffCommentCardChrome` in one pass: the drop shadow that lifts the card off the diff, an
    /// opaque tinted fill, then the hairline. The fill has to be opaque — the wash bands pass
    /// behind the card, and a translucent one would let the neighbouring diff colours through.
    func drawCard() {
        let rect = card.frame.insetBy(dx: 0.5, dy: 0.5)
        let path = NSBezierPath(roundedRect: rect, xRadius: Self.cornerRadius, yRadius: Self.cornerRadius)
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.appKitResolvedColor(in: self, alpha: 0.2)
        shadow.shadowBlurRadius = 5
        // The view is flipped, so a positive offset falls downward like the pane's `.shadow(y: 1)`.
        shadow.shadowOffset = NSSize(width: 0, height: 1)
        shadow.set()
        let base = NSColor.textBackgroundColor.appKitResolvedColor(in: self, alpha: 1)
        let tint = NSColor.secondaryLabelColor.appKitResolvedColor(in: self, alpha: 1)
        (base.blended(withFraction: 0.08, of: tint) ?? base).setFill()
        path.fill()
        NSGraphicsContext.restoreGraphicsState()
        NSColor.labelColor.appKitResolvedColor(in: self, alpha: 0.1).setStroke()
        path.lineWidth = 1
        path.stroke()
    }

    func drawBand(kind: DiffCodeHighlighting.LineKind, in rect: NSRect) {
        if let wash = AppKitDiffCodeBlockPalette.rowWash(for: kind) {
            wash.setFill()
            rect.fill()
        }
        AppKitDiffCodeBlockPalette.gutterWash(for: kind).setFill()
        AppKitDiffGutterPainter.gutterRect(in: rect, metrics: metrics).fill()
    }
}
