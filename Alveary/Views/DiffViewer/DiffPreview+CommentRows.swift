import SwiftUI

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
    /// into the viewer's server-side draft. Only the review-proposal card renders these, and the
    /// array position is the only identity a staged comment has, so it is what the card's Remove
    /// addresses. Every removal shifts the array, so a pruned preview must renumber what survives —
    /// the one mutable field here, so that renumbering cannot silently drop a sibling.
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

/// Fits comment rows to the visible pane instead of the horizontally scrollable
/// diff width, so composing never requires horizontal scrolling.
struct DiffCommentRowWidthModifier: ViewModifier {
    @Environment(\.diffPreviewViewportContentWidth) private var viewportWidth

    func body(content: Content) -> some View {
        if viewportWidth > 0 {
            content.frame(width: viewportWidth, alignment: .leading)
        } else {
            content.frame(maxWidth: 640, alignment: .leading)
        }
    }
}

/// Interior padding for comment cards: 10pt except trailing, which matches the
/// Overview timeline cards' 12pt so the three-dot menu sits the same distance
/// from its card's right edge on both tabs. With the card's 8pt horizontal
/// outset and the diff content's 6pt inset, trailing controls end 26pt from
/// the scroll view's edge — 9pt clear of the 17pt overlay indicator lane
/// (the clicks that dropped were at 3pt clearance or less).
struct DiffCommentCardInteriorPadding: ViewModifier {
    static let basePadding: CGFloat = 10
    static let trailingPadding: CGFloat = 12

    func body(content: Content) -> some View {
        content
            .padding(.vertical, Self.basePadding)
            .padding(.leading, Self.basePadding)
            .padding(.trailing, Self.trailingPadding)
    }
}

/// The full card treatment shared by thread and composer rows: interior
/// padding, the rounded fill, then an 8pt horizontal / 4pt vertical outset so
/// the hunk's code surface shows around the card and it reads as floating on
/// the diff rather than sitting on a full-width backdrop band.
struct DiffCommentCardChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
            .modifier(DiffCommentCardInteriorPadding())
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(cardFill)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .modifier(DiffCommentRowWidthModifier())
    }

    /// Opaque base under the tint: the row's wash bands pass the neighboring
    /// line colors around the card, and without the base they would also tint
    /// the card's interior through its translucent fill. The hairline stroke
    /// and drop shadow keep the card separated when the anchored line is
    /// context — a clear wash leaves fill and surface nearly the same color.
    private var cardFill: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.secondary.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.2), radius: 5, y: 1)
    }
}

struct DiffCommentThreadRow: View {
    let thread: DiffLineCommentThread
    let anchor: DiffCommentAnchor
    let interaction: DiffCommentInteraction?

    /// Resolved threads collapse to their header; this remembers an explicit expand.
    /// Resolution changes reset it, so resolving collapses and unresolving expands.
    @State private var isManuallyExpanded = false

    private var showsContent: Bool {
        !thread.isResolved || isManuallyExpanded
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if thread.isResolved {
                resolvedHeader
            }

            if showsContent {
                ForEach(Array(thread.comments.enumerated()), id: \.offset) { _, comment in
                    commentView(comment)
                }

                threadFooter
            }
        }
        .modifier(DiffCommentCardChrome())
        .onChange(of: thread.isResolved) { _, _ in
            isManuallyExpanded = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comments on line \(anchor.line) of \(anchor.path)")
    }

    private var resolvedHeader: some View {
        PullRequestResolvedThreadHeader(commentCount: thread.comments.count, isExpanded: $isManuallyExpanded)
    }

    @ViewBuilder
    private func commentView(_ comment: DiffLineComment) -> some View {
        let isEditing = isEditingInline(comment)
        VStack(alignment: .leading, spacing: 8) {
            PullRequestCommentAuthorRow(
                login: comment.author,
                avatarURL: comment.avatarURL,
                isBot: comment.isBot,
                avatarLoader: interaction?.avatarLoader
            ) {
                // Both mean "unpublished", so they share a tint, but they are different
                // states: "Proposed" is staged in Alveary's review-proposal envelope and
                // exists nowhere on GitHub, while "Pending" is the viewer's server-side
                // draft. Mutually exclusive by construction — a staged comment is never
                // `isPending` — and the `else` keeps it that way.
                if comment.isProposed {
                    PullRequestCommentBadge("Proposed", color: .orange)
                } else if comment.isPending {
                    PullRequestCommentBadge("Pending", color: .orange)
                }
                if thread.isResolved {
                    Text("Resolved")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
                if thread.isOutdated {
                    PullRequestCommentBadge("Outdated", color: .orange)
                }

                Spacer(minLength: 0)

                // Timestamp sits trailing, just left of the three-dot menu,
                // matching the Overview timeline's comment cards.
                if let relativeAge = comment.relativeAge, let absolute = comment.absoluteTimestamp {
                    PullRequestTimestampLabel(relative: relativeAge, absolute: absolute)
                }

                if !isEditing {
                    commentActions(for: comment)
                }
            }

            if isEditing, let interaction {
                DiffCommentEditorControls(anchor: anchor, interaction: interaction)
            } else {
                AppMarkdownText(markdown: comment.bodyMarkdown)

                if !comment.isPending, comment.nodeID != nil, let interaction {
                    CommentReactionBar(
                        reactions: comment.reactions,
                        options: interaction.reactionOptions,
                        onToggle: { content in
                            interaction.onToggleReaction(comment, content)
                        }
                    )
                }
            }
        }
    }

    /// Inline editing swaps the comment's body for the shared editor controls,
    /// keeping the author row in place.
    private func isEditingInline(_ comment: DiffLineComment) -> Bool {
        guard let interaction else {
            return false
        }
        if let remoteID = comment.remoteID, !comment.isPending, interaction.editingRemoteCommentID == remoteID {
            return true
        }
        guard comment.isPending, let nodeID = comment.nodeID else {
            return false
        }
        return interaction.editingPendingCommentNodeID == nodeID
    }

    /// The shared Reply / Resolve footer; needs an interaction plus a submitted
    /// root comment for replies to attach to. A pending thread offers neither
    /// until its review is submitted.
    @ViewBuilder
    private var threadFooter: some View {
        if let interaction, !thread.isPending, thread.replyTargetCommentID != nil {
            PullRequestThreadActionsFooter(
                isResolved: thread.isResolved,
                canReply: true,
                canResolve: thread.threadID != nil,
                onReply: { interaction.onReplyToThread(anchor, thread) },
                onToggleResolved: { interaction.onToggleThreadResolved(anchor, thread) }
            )
        }
    }

    /// Pending and submitted comments share the same three-dot menu and the same
    /// permission gating; only the id the actions are addressed by differs — a
    /// node id when pending, a REST id when submitted. A pending comment still
    /// awaiting GitHub's answer has neither, so it offers no actions until the
    /// real thread swaps in.
    @ViewBuilder
    private func commentActions(for comment: DiffLineComment) -> some View {
        let hasActionableID = comment.isPending ? comment.nodeID != nil : comment.remoteID != nil
        // A staged comment is removed, never edited — remove and re-add is the path. It wears the
        // same menu as every other comment on this card rather than the transcript's two-press
        // pill, so the pane keeps one comment-control shape on one trailing column.
        if let interaction, let proposedIndex = comment.proposedIndex,
           let onRemoveProposedComment = interaction.onRemoveProposedComment {
            PullRequestCommentActionsMenu(
                onEdit: nil,
                onDelete: { onRemoveProposedComment(proposedIndex) }
            )
        } else if let interaction, comment.canEdit || comment.canDelete, hasActionableID {
            PullRequestCommentActionsMenu(
                onEdit: comment.canEdit ? { interaction.onEditRemoteComment(anchor, comment) } : nil,
                onDelete: deleteAction(for: comment, interaction: interaction)
            )
        }
    }

    /// Deleting an unsubmitted comment goes straight through — nothing is
    /// published yet, so GitHub (and Alveary) skip the confirmation a submitted
    /// comment's deletion arms.
    private func deleteAction(
        for comment: DiffLineComment,
        interaction: DiffCommentInteraction
    ) -> (() -> Void)? {
        guard comment.canDelete else {
            return nil
        }
        if comment.isPending {
            return { interaction.onDeletePending(comment) }
        }
        return { interaction.onDeleteRemoteComment(anchor, comment) }
    }
}

/// Wraps a diff line row with a hover "add comment" affordance over the gutter's
/// marker column — the `+`/`-` slot directly beside the code text, like GitHub.
struct DiffCommentableLineRow<Content: View>: View {
    let anchor: DiffCommentAnchor
    let gutterLayout: DiffGutterLayout
    let onAddComment: (DiffCommentAnchor) -> Void
    @ViewBuilder let content: Content

    @State private var isHovered = false

    var body: some View {
        content
            .overlay(alignment: .leading) {
                if isHovered {
                    Button {
                        onAddComment(anchor)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 16))
                            // Palette rendering fills the plus cutout; with a
                            // single style the glyph is transparent and the hovered
                            // line's background bleeds through it. Dark fill: a
                            // white plus washes out against the gold accent circle.
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.black.opacity(0.85), Color.accentColor)
                    }
                    .buttonStyle(DiffCommentPlusButtonStyle())
                    .frame(width: gutterLayout.markerWidth, alignment: .center)
                    .padding(.leading, gutterLayout.lineNumberColumnsWidth)
                    .help("Add a comment on this line")
                    .accessibilityLabel("Comment on line \(anchor.line)")
                }
            }
            // Hover is tracked after the overlay so the button sits inside its own
            // hover region; tracking on the content alone made the button steal the
            // pointer and flicker away on small movements.
            .onHover { hovering in
                isHovered = hovering
            }
    }
}

/// Pressed feedback for the hover add-comment affordance; the overlay placement
/// means the larger glyph never affects diff line row height.
private struct DiffCommentPlusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Circle())
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.88 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
