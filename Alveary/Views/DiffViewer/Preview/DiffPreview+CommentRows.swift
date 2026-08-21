import SwiftUI

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

    /// Namespaces this comment's interactive markdown state — `<details>` expansion, task
    /// checkboxes — which is otherwise keyed by body text alone. Two bots posting the same
    /// "Test run logs" section on different lines would share one disclosure and open together.
    ///
    /// A staged comment exists nowhere on GitHub, so its array position plus the line it annotates
    /// is the only identity it has.
    private func markdownStateScope(for comment: DiffLineComment) -> String {
        if let nodeID = comment.nodeID {
            return nodeID
        }
        if let remoteID = comment.remoteID {
            return "rest:\(remoteID)"
        }
        return "staged:\(anchor.key):\(comment.proposedIndex ?? -1)"
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
        PullRequestResolvedThreadHeader(commentCount: thread.commentCount, isExpanded: $isManuallyExpanded)
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
                AppMarkdownText(
                    markdown: comment.bodyMarkdown,
                    taskStateScope: markdownStateScope(for: comment)
                )

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
