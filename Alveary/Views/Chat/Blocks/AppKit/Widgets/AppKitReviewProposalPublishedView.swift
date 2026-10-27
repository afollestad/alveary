import AppKit

/// What a submitted card's comment cards need beyond each comment: whether this conversation may
/// change them, and each one's unsanitized body and evidence by node id.
struct AppKitReviewProposalPublishedComments: Equatable {
    let allowsActions: Bool
    let comments: [String: PullRequestPublishedReview.Comment]
}

/// A submitted review's body: its published comments on the lines they annotate, editable and
/// deletable on GitHub as GitHub permits, and the way to the pull request.
///
/// Its subviews stay mounted across configurations, because a diff built from new views would discard
/// a comment card's open editor.
@MainActor
final class AppKitReviewProposalPublishedView: NSView {
    struct Configuration: Equatable {
        let proposalID: String
        let published: ReviewProposalWidgetState.Published
        let typography: TranscriptTypography
    }

    /// Each carries the proposal id first, then the comment's node id or anchor.
    var onEditComment: (@MainActor (String, String, String) async -> Bool)?
    var onDeleteComment: ((String, String) -> Void)?
    var onJumpToComment: ((String, DiffCommentAnchor) -> Void)?
    var onOpenPullRequest: ((PullRequestIdentifier) -> Void)?
    var onOpenLink: ((URL) -> Void)?
    var onHeightInvalidated: (() -> Void)?
    var onImmediateHeightInvalidated: (() -> Void)?
    var avatarLoader: GitHubAvatarLoader?

    private let stack = NSStackView()
    private let caption = AppKitTranscriptWidgetLabelFactory.label(
        "", level: .caption, color: .secondaryLabelColor, typography: TranscriptTypography(), wraps: true
    )
    private let diffView = AppKitReviewProposalDiffView()
    private let errorLabel = AppKitTranscriptWidgetLabelFactory.label(
        "", level: .caption, color: .systemRed, typography: TranscriptTypography(), wraps: true
    )
    private lazy var openButton = AppKitReviewProposalWidgetView.button(
        title: "Open PR", icon: .octicon(.pullRequest16), style: .secondary, target: self, action: #selector(openPullRequest)
    )
    private var configuration: Configuration?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
        stack.addFullWidthArrangedSubview(caption)
        stack.addFullWidthArrangedSubview(diffView)
        stack.addFullWidthArrangedSubview(errorLabel)
        stack.addArrangedSubview(openButton)
        wireDiffView()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var naturalWidth: CGFloat {
        [
            diffView.isHidden ? 0 : min(diffView.naturalWidth, AppKitReviewProposalWidgetView.maximumDiffWidth),
            ceil(caption.fittingSize.width),
            errorLabel.isHidden ? 0 : ceil(errorLabel.fittingSize.width),
            ceil(openButton.fittingSize.width)
        ].max() ?? 0
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else { return }
        self.configuration = configuration
        let published = configuration.published
        let typography = configuration.typography
        caption.font = typography.nsFont(.caption)
        caption.stringValue = Self.summary(published.review)
        errorLabel.font = typography.nsFont(.caption)
        errorLabel.stringValue = published.errorMessage ?? ""
        errorLabel.isHidden = published.errorMessage == nil
        let preview = published.review.preview
        diffView.isHidden = preview.files.isEmpty
        // Before `configure`, which skips an unchanged preview and would leave the cards without either.
        diffView.avatarLoader = avatarLoader
        diffView.busyCommentIDs = published.busyCommentIDs
        diffView.configure(.init(
            preview: preview,
            typography: typography,
            allowsRemoval: false,
            allowsJumping: published.allowsActions,
            evidenceByProposedIndex: [:],
            reviewers: published.review.reviewers,
            published: AppKitReviewProposalPublishedComments(
                allowsActions: published.allowsActions,
                comments: Dictionary(published.review.liveComments.map { ($0.nodeID, $0) }) { first, _ in first }
            )
        ))
        // The action row's clearance follows whichever row ends up above it, as on the pending card.
        let rows = [caption, diffView, errorLabel]
        let last = rows.last { !$0.isHidden }
        for row in rows {
            stack.setCustomSpacing(row === last ? AppKitReviewProposalWidgetView.actionRowSeparation : stack.spacing, after: row)
        }
    }

    /// The live comments only; one GitHub deleted reads as gone rather than as a dead card. A comment the
    /// hunks cannot place (a file past the cap, or a diff confirm could not fetch) is counted, not dropped.
    static func summary(_ review: PullRequestPublishedReview) -> String {
        let count = review.liveComments.count
        guard count > 0 else { return "The published comments were deleted." }
        let summary = "Published \(count) review comment\(count == 1 ? "" : "s")."
        let hidden = review.liveComments.filter { !review.draws($0) }.count
        guard hidden > 0 else { return summary }
        return summary + " \(hidden) \(hidden == 1 ? "is" : "are") not shown; open the pull request to read \(hidden == 1 ? "it" : "them")."
    }

    @objc private func openPullRequest() {
        guard let identifier = configuration?.published.review.identifier else { return }
        onOpenPullRequest?(identifier)
    }

    private func wireDiffView() {
        diffView.onHeightInvalidated = { [weak self] in self?.onHeightInvalidated?() }
        diffView.onImmediateHeightInvalidated = { [weak self] in self?.onImmediateHeightInvalidated?() }
        diffView.onOpenLink = { [weak self] url in self?.onOpenLink?(url) }
        diffView.onJumpToProposedComment = { [weak self] anchor in
            guard let self, let id = configuration?.proposalID else { return }
            onJumpToComment?(id, anchor)
        }
        diffView.onEditPublishedComment = { [weak self] nodeID, body in
            guard let self, let id = configuration?.proposalID else { return false }
            return await onEditComment?(id, nodeID, body) ?? false
        }
        diffView.onDeletePublishedComment = { [weak self] nodeID in
            guard let self, let id = configuration?.proposalID else { return }
            onDeleteComment?(id, nodeID)
        }
    }
}

extension PullRequestPublishedReview {
    /// The snapshot in the diff view's terms: the live comments at their anchors, attributed to the
    /// viewer, over the hunks they sit on.
    var preview: PullRequestReviewProposalPreview {
        var annotations = DiffCommentAnnotations()
        for comment in liveComments {
            annotations.threads[comment.anchor, default: DiffLineCommentThread(comments: [])].comments.append(DiffLineComment(
                author: viewerLogin ?? "You",
                bodyMarkdown: PullRequestMarkdown.sanitized(comment.bodyMarkdown),
                isPending: false,
                nodeID: comment.nodeID,
                canEdit: comment.viewerCanUpdate,
                canDelete: comment.viewerCanDelete,
                avatarURL: viewerAvatarURL
            ))
        }
        return PullRequestReviewProposalPreview(
            files: ReviewProposalDiffNarrowing.narrowed(
                files: files, linesByPath: liveComments.reduce(into: [:]) { $0[$1.path, default: []].insert($1.line) }
            ),
            annotations: annotations,
            pendingCommentCount: 0,
            proposedCommentCount: 0,
            hiddenFileCount: 0,
            staleComments: [],
            viewerIsAuthor: false
        )
    }

    /// Whether a hunk holds the comment's line on its side, which is what lets the diff view place it.
    func draws(_ comment: Comment) -> Bool {
        files.contains { file in
            file.path == comment.path && file.hunks.contains { hunk in
                hunk.lines.contains { (comment.anchor.side == .left ? $0.oldLineNumber : $0.newLineNumber) == comment.line }
            }
        }
    }
}
