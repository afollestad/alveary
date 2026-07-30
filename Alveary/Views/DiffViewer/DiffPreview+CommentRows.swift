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
    /// Pending comments are local batch entries that have not been submitted yet.
    let isPending: Bool
    /// REST id of a submitted comment; required to edit it in place.
    let remoteID: Int?
    /// GraphQL node id of a submitted comment; required to react to it.
    let nodeID: String?
    /// Permission-based (GitHub's `viewerCanUpdate`/`viewerCanDelete`), so repo
    /// collaborators get the menu on comments they did not author.
    let canEdit: Bool
    let canDelete: Bool
    let reactions: [CommentReaction]
    let avatarURL: URL?
    let isBot: Bool

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
        isBot: Bool = false
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
    }
}

struct DiffLineCommentThread: Hashable, Sendable {
    var comments: [DiffLineComment]
    var isResolved = false
    var isOutdated = false
    /// GraphQL node id of the backing review thread; enables resolve/unresolve.
    var threadID: String?

    /// The REST id replies attach to — GitHub replies always target the root comment.
    var replyTargetCommentID: Int? {
        comments.first { $0.remoteID != nil }?.remoteID
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
    /// The pending-batch comment (keyed by anchor) being edited inline.
    let editingPendingAnchor: DiffCommentAnchor?
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
    let onDeletePending: (DiffCommentAnchor) -> Void
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
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
        .padding(.vertical, 6)
        .modifier(DiffCommentRowWidthModifier())
        .onChange(of: thread.isResolved) { _, _ in
            isManuallyExpanded = false
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Comments on line \(anchor.line) of \(anchor.path)")
    }

    private var resolvedHeader: some View {
        Button {
            isManuallyExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isManuallyExpanded ? 90 : 0))

                Text("Resolved")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)

                Text("\(thread.comments.count) comment\(thread.comments.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Resolved conversation, \(thread.comments.count) comments")
        .accessibilityHint(isManuallyExpanded ? "Collapses the conversation" : "Expands the conversation")
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
                if comment.isPending {
                    orangeCapsuleBadge("Pending")
                }
                if thread.isResolved {
                    Text("Resolved")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
                if thread.isOutdated {
                    orangeCapsuleBadge("Outdated")
                }

                Spacer(minLength: 0)

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
        if let remoteID = comment.remoteID, interaction.editingRemoteCommentID == remoteID {
            return true
        }
        return comment.isPending && interaction.editingPendingAnchor == anchor
    }

    /// Reply and resolve, GitHub style. Both need a submitted thread: replies attach
    /// to the root remote comment, resolution needs the thread's node id.
    @ViewBuilder
    private var threadFooter: some View {
        if let interaction, thread.replyTargetCommentID != nil {
            HStack(spacing: 12) {
                Button("Reply") {
                    interaction.onReplyToThread(anchor, thread)
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(Color.accentColor)
                .accessibilityLabel("Reply to thread")

                if thread.threadID != nil {
                    Button(thread.isResolved ? "Unresolve conversation" : "Resolve conversation") {
                        interaction.onToggleThreadResolved(anchor, thread)
                    }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)
            }
            .padding(.top, 2)
        }
    }

    private func orangeCapsuleBadge(_ text: String) -> some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(Color.orange.opacity(0.14)))
            .foregroundStyle(.orange)
    }

    /// Pending and submitted comments share the same three-dot menu; only the
    /// available actions differ (pending: always both, submitted: permission-gated).
    @ViewBuilder
    private func commentActions(for comment: DiffLineComment) -> some View {
        if let interaction {
            if comment.isPending {
                actionsMenu(
                    onEdit: { interaction.onAddComment(anchor) },
                    onDelete: { interaction.onDeletePending(anchor) }
                )
            } else if comment.canEdit || comment.canDelete, comment.remoteID != nil {
                actionsMenu(
                    onEdit: comment.canEdit ? { interaction.onEditRemoteComment(anchor, comment) } : nil,
                    onDelete: comment.canDelete ? { interaction.onDeleteRemoteComment(anchor, comment) } : nil
                )
            }
        }
    }

    private func actionsMenu(onEdit: (() -> Void)?, onDelete: (() -> Void)?) -> some View {
        Menu {
            if let onEdit {
                Button("Edit", action: onEdit)
            }
            if let onDelete {
                Button("Delete", role: .destructive, action: onDelete)
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                // The bare glyph is a sliver; give the control a real hit target.
                .frame(width: 26, height: 20)
                .contentShape(Rectangle())
        }
        .menuStyle(.button)
        .menuIndicator(.hidden)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Comment actions")
        .accessibilityLabel("Comment actions")
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
                            // Palette rendering fills the plus cutout white; with a
                            // single style the glyph is transparent and the hovered
                            // line's background bleeds through it.
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Color.accentColor)
                    }
                    .buttonStyle(DiffCommentPlusButtonStyle())
                    .frame(width: gutterLayout.markerWidth, alignment: .center)
                    .padding(.leading, lineNumbersWidth)
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

    private var lineNumbersWidth: CGFloat {
        let columnWidth = gutterLayout.lineNumberWidth + gutterLayout.lineNumberTrailingPadding
        let oldWidth = gutterLayout.showsOldLineNumbers ? columnWidth : 0
        let newWidth = gutterLayout.showsNewLineNumbers ? columnWidth : 0
        return oldWidth + newWidth
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
