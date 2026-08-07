import AppKit

/// The pending review comments on the diff lines they were written against, rendered natively with
/// the same gutter a fenced diff block gets.
///
/// This deliberately does not host `FlattenedDiffPreview`: that view wraps its rows in a
/// `ScrollView`, which reports no intrinsic height, so a transcript row measuring itself from its
/// content gets a collapsed card with its controls laid over the clipped diff. It is not one
/// `AppKitDiffCodeBlockView` either — that view puts every row in a single text view, which cannot
/// interleave comment cards, and per-hunk segments would each compute their own gutter width and
/// vertical padding. So the rows stack, and each draws its own slice through
/// `AppKitDiffGutterPainter`. A transcript card cannot scroll anyway — the preview is already
/// narrowed to the commented hunks, and the whole diff stays one Open PR away.
///
/// It wears the shared code-block border and radius so the slab ends at an edge of its own rather
/// than needing a rule across the card, and so a review's diff reads like every other fenced block
/// in the transcript. Nothing about those blocks changes here — this adopts their treatment.
@MainActor
final class AppKitReviewProposalDiffView: AppKitDynamicColorView {
    /// A comment card's markdown body can grow after an inline image loads, so the card's height
    /// change has to reach the transcript row that measured it.
    var onHeightInvalidated: (() -> Void)?
    /// Absent in snapshots and previews, which is what makes avatars fall back to their initials.
    var avatarLoader: GitHubAvatarLoader?
    /// Opens a link inside a comment's markdown body.
    var onOpenLink: ((URL) -> Void)?
    /// Drops a staged comment from the review, by its position in the stored envelope.
    var onRemoveProposedComment: ((Int) -> Void)?

    private let stack = NSStackView()
    private var renderedPreview: PullRequestReviewProposalPreview?
    private var renderedTypography: TranscriptTypography?
    private var renderedAllowsRemoval = false
    /// Rebuilt views are reused rather than reconstructed. The chat font-size setting is a live
    /// slider, so every step reconfigures this view; rebuilding from scratch would recreate a
    /// markdown body and refire an avatar load per comment on each one.
    private var rowViewPool: [AppKitReviewProposalDiffRowView] = []
    private var cardViewPool: [AppKitReviewProposalCommentCardView] = []
    /// Summed at rebuild, because the widget queries it while measuring itself.
    private var widestRow: CGFloat = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        wantsLayer = true
        layer?.cornerRadius = AppKitMarkdownMetrics.codeCornerRadius
        layer?.borderWidth = 1
        // The rows paint edge to edge, so they have to be clipped to the rounded corners; the
        // border itself follows the appearance through the shared provider.
        layer?.masksToBounds = true
        setLayerStrokeColor(provider: { AppMarkdownCodeBlockPalette.borderNSColor(for: $0) })
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 0
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool {
        true
    }

    var hasContent: Bool {
        !stack.arrangedSubviews.isEmpty
    }

    func configure(
        preview: PullRequestReviewProposalPreview,
        typography: TranscriptTypography,
        allowsRemoval: Bool
    ) {
        guard renderedPreview != preview
            || renderedTypography != typography
            || renderedAllowsRemoval != allowsRemoval else {
            return
        }
        renderedPreview = preview
        renderedTypography = typography
        renderedAllowsRemoval = allowsRemoval
        rebuild(preview: preview, typography: typography, allowsRemoval: allowsRemoval)
    }

    /// The widest rendered row, so the card can size to its content like every other widget body.
    /// Comment cards wrap, so only the diff rows have a natural width worth honouring.
    var naturalWidth: CGFloat {
        widestRow
    }
}

private extension AppKitReviewProposalDiffView {
    /// One stacked entry: a diff line drawn with the gutter, or a comment floating over it.
    enum Item {
        case row(DiffCodeHighlighting.Row)
        case comment(DiffLineComment, DiffCommentAnchor, anchoredKind: DiffCodeHighlighting.LineKind)
    }

    func rebuild(
        preview: PullRequestReviewProposalPreview,
        typography: TranscriptTypography,
        allowsRemoval: Bool
    ) {
        // Detached, not discarded: the pools below hand the same views back, so a rebuild costs
        // reconfiguration instead of reconstruction. Removing from the superview is what retires
        // each view's full-width constraint, which `addFullWidthArrangedSubview` makes anew.
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        let items = items(in: preview)
        let font = NSFont.monospacedSystemFont(ofSize: typography.size(for: .caption), weight: .regular)
        // One metrics value for the whole preview, so every file's gutter lines up.
        let metrics = AppKitDiffCodeBlockMetrics(rows: items.compactMap(\.row), font: font)
        let context = AppKitReviewProposalCommentContext(
            typography: typography,
            avatarLoader: avatarLoader,
            allowsRemoval: allowsRemoval
        )
        var rowCount = 0
        var cardCount = 0
        widestRow = 0
        for (index, item) in items.enumerated() {
            switch item {
            case .row(let row):
                let view = rowView(at: rowCount)
                rowCount += 1
                view.configure(row: row, metrics: metrics, font: font)
                widestRow = max(widestRow, view.naturalWidth)
                stack.addFullWidthArrangedSubview(view)
            case .comment(let comment, let anchor, let anchoredKind):
                let view = cardView(at: cardCount)
                cardCount += 1
                view.configure(
                    comment: comment,
                    anchor: anchor,
                    wash: AppKitReviewProposalCommentWash(
                        top: anchoredKind,
                        bottom: Self.followingRowKind(after: index, in: items),
                        isTrailing: index == items.count - 1
                    ),
                    metrics: metrics,
                    context: context
                )
                stack.addFullWidthArrangedSubview(view)
            }
        }
        rowViewPool.removeSubrange(rowCount...)
        cardViewPool.removeSubrange(cardCount...)
    }

    func rowView(at index: Int) -> AppKitReviewProposalDiffRowView {
        if index < rowViewPool.count {
            return rowViewPool[index]
        }
        let view = AppKitReviewProposalDiffRowView()
        rowViewPool.append(view)
        return view
    }

    func cardView(at index: Int) -> AppKitReviewProposalCommentCardView {
        if index < cardViewPool.count {
            return cardViewPool[index]
        }
        let view = AppKitReviewProposalCommentCardView()
        view.onHeightInvalidated = { [weak self] in
            self?.onHeightInvalidated?()
        }
        view.onOpenLink = { [weak self] url in
            self?.onOpenLink?(url)
        }
        view.onRemove = { [weak self] index in
            self?.onRemoveProposedComment?(index)
        }
        cardViewPool.append(view)
        return view
    }

    /// The kind the card's lower wash band continues. A card at the end of the preview has no
    /// following line, so its band falls back to the untinted context wash.
    static func followingRowKind(after index: Int, in items: [Item]) -> DiffCodeHighlighting.LineKind {
        items[(index + 1)...].lazy.compactMap(\.row).first?.kind ?? .context
    }

    func items(in preview: PullRequestReviewProposalPreview) -> [Item] {
        preview.files.flatMap { file in
            [Item.row(DiffCodeHighlighting.Row(kind: .fileHeader, text: file.path, oldNumber: nil, newNumber: nil))]
                + file.hunks.flatMap { hunk in
                    items(in: hunk, file: file, preview: preview)
                }
        }
    }

    /// Lines within `contextRadius` of a commented line render; the rest collapse into ellipsis
    /// rows. A hunk can span hundreds of lines and the card cannot scroll, so the anchor context
    /// is the part worth the height — the whole diff stays one Open PR away.
    static let contextRadius = 3

    func items(
        in hunk: DiffHunk,
        file: DiffFile,
        preview: PullRequestReviewProposalPreview
    ) -> [Item] {
        let anchoredIndexes = hunk.lines.indices.filter { index in
            !threads(at: hunk.lines[index], path: file.path, preview: preview).isEmpty
        }
        var items: [Item] = []
        var didElide = false
        for (index, line) in hunk.lines.enumerated() {
            let isNearAnchor = anchoredIndexes.contains { abs($0 - index) <= Self.contextRadius }
            guard isNearAnchor else {
                if !didElide {
                    items.append(.row(DiffCodeHighlighting.Row(kind: .hunkHeader, text: "⋯", oldNumber: nil, newNumber: nil)))
                    didElide = true
                }
                continue
            }
            didElide = false
            let kind = DiffCodeHighlighting.LineKind(line.type)
            items.append(
                .row(
                    DiffCodeHighlighting.Row(
                        kind: kind,
                        text: line.content,
                        oldNumber: line.oldLineNumber,
                        newNumber: line.newLineNumber
                    )
                )
            )
            for (anchor, thread) in threads(at: line, path: file.path, preview: preview) {
                items.append(contentsOf: thread.comments.map { .comment($0, anchor, anchoredKind: kind) })
            }
        }
        return items
    }

    /// A comment anchors on whichever side's number it was written against, matching the GitHub
    /// review API: added and context lines on the right, deleted lines on the left.
    func threads(
        at line: DiffLine,
        path: String,
        preview: PullRequestReviewProposalPreview
    ) -> [(anchor: DiffCommentAnchor, thread: DiffLineCommentThread)] {
        var anchors: [DiffCommentAnchor] = []
        if let newLine = line.newLineNumber {
            anchors.append(DiffCommentAnchor(path: path, side: .right, line: newLine))
        }
        if let oldLine = line.oldLineNumber {
            anchors.append(DiffCommentAnchor(path: path, side: .left, line: oldLine))
        }
        return anchors.compactMap { anchor in
            preview.annotations.threads[anchor].map { (anchor, $0) }
        }
    }
}

private extension AppKitReviewProposalDiffView.Item {
    var row: DiffCodeHighlighting.Row? {
        guard case .row(let row) = self else {
            return nil
        }
        return row
    }
}
