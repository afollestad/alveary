import Foundation

/// Anchors a diff comment the way the GitHub review API does: file path, diff side,
/// and the line number on that side.
struct DiffCommentAnchor: Hashable, Sendable {
    enum Side: String, Hashable, Sendable {
        case left = "LEFT"
        case right = "RIGHT"
    }

    let path: String
    let side: Side
    let line: Int

    var key: String {
        "\(path):\(side.rawValue):\(line)"
    }
}

struct DiffLineComment: Hashable, Sendable {
    let author: String
    let bodyMarkdown: String
    /// Written into the viewer's draft review on GitHub but not yet submitted.
    /// Pending comments are edited and deleted by `nodeID`, not `remoteID`.
    let isPending: Bool
    /// REST id of a submitted comment; required to edit it in place.
    let remoteID: Int?
    /// GraphQL node id; required to react to a submitted comment, and to edit or
    /// delete a pending one.
    let nodeID: String?
    /// Permission-based (GitHub's `viewerCanUpdate`/`viewerCanDelete`), so repo
    /// collaborators get the menu on comments they did not author.
    let canEdit: Bool
    let canDelete: Bool
    let reactions: [CommentReaction]
    let avatarURL: URL?
    let isBot: Bool
    /// Preformatted at annotation-build time — once per detail change — so the
    /// lazily recycled rows never touch a date formatter on scroll-back-in. The
    /// tooltip/accessibility string beside it carries the absolute date and time.
    let relativeAge: String?
    let absoluteTimestamp: String?
    /// Position in the review proposal's stored `comments` array, for a comment staged inside a
    /// proposal and existing nowhere on GitHub yet — narrower than `isPending`, which means written
    /// into the viewer's server-side draft. The review-proposal card and the pull request pane both
    /// render these, and the array position is the only identity a staged comment has, so it is what
    /// Remove addresses on either. Every removal shifts the array, so a pruned preview must renumber
    /// what survives — the one mutable field here, so that renumbering cannot silently drop a
    /// sibling. Additions append for the same reason: an insert would move a rendered card's index.
    var proposedIndex: Int?

    var isProposed: Bool {
        proposedIndex != nil
    }

    init(
        author: String,
        bodyMarkdown: String,
        isPending: Bool,
        remoteID: Int? = nil,
        nodeID: String? = nil,
        canEdit: Bool = false,
        canDelete: Bool = false,
        reactions: [CommentReaction] = [],
        avatarURL: URL? = nil,
        isBot: Bool = false,
        relativeAge: String? = nil,
        absoluteTimestamp: String? = nil,
        proposedIndex: Int? = nil
    ) {
        self.author = author
        self.bodyMarkdown = bodyMarkdown
        self.isPending = isPending
        self.remoteID = remoteID
        self.nodeID = nodeID
        self.canEdit = canEdit
        self.canDelete = canDelete
        self.reactions = reactions
        self.avatarURL = avatarURL
        self.isBot = isBot
        self.relativeAge = relativeAge
        self.absoluteTimestamp = absoluteTimestamp
        self.proposedIndex = proposedIndex
    }
}

struct DiffLineCommentThread: Hashable, Sendable {
    var comments: [DiffLineComment]
    var isResolved = false
    var isOutdated = false
    /// GraphQL node id of the backing review thread; enables resolve/unresolve.
    var threadID: String?
    /// The viewer's own unsubmitted thread. GitHub accepts neither replies nor
    /// resolution on one until the review is submitted, so the footer hides.
    var isPending = false
    /// GitHub's own count when it exceeded the fetched page; nil means `comments` is whole.
    var totalCommentCount: Int?

    var commentCount: Int { max(totalCommentCount ?? comments.count, comments.count) }

    /// The REST id replies attach to — GitHub replies always target the root
    /// comment. Pending comments are skipped; they cannot be replied to.
    var replyTargetCommentID: Int? {
        comments.first { $0.remoteID != nil && !$0.isPending }?.remoteID
    }
}

/// The value half of diff comment support: which anchors carry threads, where the
/// composer sits, and whether line rows offer the hover "add comment" affordance.
/// `Sendable` and hashable so off-main row preparation and the render fingerprint
/// can consume it. `.none` keeps the diff viewer's row stream byte-identical.
struct DiffCommentAnnotations: Hashable, Sendable {
    static let none = DiffCommentAnnotations()

    var threads: [DiffCommentAnchor: DiffLineCommentThread] = [:]
    var composerAnchor: DiffCommentAnchor?
    var allowsComposing = false

    var isActive: Bool {
        allowsComposing || composerAnchor != nil || !threads.isEmpty
    }
}

enum DiffCommentComposerMode {
    case newComment
    case editPending
    case editRemote
    case reply

    var saveTitle: String {
        switch self {
        case .newComment:
            return "Add comment"
        case .editPending:
            return "Save comment"
        case .editRemote:
            return "Update comment"
        case .reply:
            return "Reply"
        }
    }

    /// Travels with `saveTitle`; reply takes the thread footer's reply glyph,
    /// every other mode the comment glyph.
    var saveIcon: ActionIcon {
        switch self {
        case .newComment, .editPending, .editRemote:
            return .octicon(.comment16)
        case .reply:
            return .octicon(.reply16)
        }
    }

    /// Drives the composer placeholder: editing an existing comment reads
    /// differently from leaving a new one.
    var isEditing: Bool {
        switch self {
        case .editPending, .editRemote:
            return true
        case .newComment, .reply:
            return false
        }
    }
}

/// The interactive half of diff comment support, view-layer only.
struct DiffCommentInteraction {
    /// The open composing session; `nil` while no composer row is mounted.
    let draft: PullRequestCommentDraftBox?
    let composerMode: (DiffCommentAnchor) -> DiffCommentComposerMode
    let composerErrorMessage: String?
    /// Token-driven first-responder request for the freshly mounted composer editor.
    let composerFocusToken: UUID?
    /// The submitted comment being edited inline in its thread. Edits render in
    /// place of the comment body; the host suppresses the standalone composer
    /// row (`DiffCommentAnnotations.composerAnchor`) while one is set.
    let editingRemoteCommentID: Int?
    /// The unsubmitted comment being edited inline, by GraphQL node id.
    let editingPendingCommentNodeID: String?
    /// The reaction palette; empty hides every reaction affordance.
    let reactionOptions: [CommentReactionOption]
    /// Renders author avatars in thread rows when present; the diff viewer's inert
    /// path never constructs an interaction, so it stays avatar-free.
    let avatarLoader: GitHubAvatarLoader?
    let onComposerFocusConsumed: () -> Void
    let onAddComment: (DiffCommentAnchor) -> Void
    let onEditRemoteComment: (DiffCommentAnchor, DiffLineComment) -> Void
    let onDeleteRemoteComment: (DiffCommentAnchor, DiffLineComment) -> Void
    let onToggleReaction: (DiffLineComment, String) -> Void
    let onReplyToThread: (DiffCommentAnchor, DiffLineCommentThread) -> Void
    let onToggleThreadResolved: (DiffCommentAnchor, DiffLineCommentThread) -> Void
    let onSaveDraft: () -> Void
    let onCancelComposer: () -> Void
    let onDeletePending: (DiffLineComment) -> Void
    /// Drops a review proposal's staged comment by its position in the stored envelope. `nil` on
    /// the diff viewer's inert path and wherever no proposal is pending, which is what keeps the
    /// action off every other comment.
    var onRemoveProposedComment: ((Int) -> Void)?
    /// Uploads local files and appends their links to the open draft. `nil` on
    /// the diff viewer's inert path, which hides the attach affordance.
    var onAttachFiles: (([URL]) -> Void)?
    /// True while an upload for the open draft is running; the host disables Save
    /// so a comment cannot post without its attachment link.
    var isUploadingAttachments = false
}

// MARK: - Row views
