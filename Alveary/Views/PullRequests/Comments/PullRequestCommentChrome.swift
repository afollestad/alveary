import SwiftUI

// Shared chrome for comment-like blocks across the Activity and Files surfaces:
// the author row (avatar + login + Bot pill), the Bot pill itself, and the
// sanitized-markdown body with its reaction bar.

extension PullRequestReactionContent {
    /// The picker palette in GitHub's order, as the shared component's model.
    static let pickerOptions: [CommentReactionOption] = allCases.map { content in
        CommentReactionOption(content: content.rawValue, emoji: content.emoji)
    }
}

extension PullRequestCommentReaction {
    var asCommentReaction: CommentReaction {
        CommentReaction(
            content: content.rawValue,
            emoji: content.emoji,
            count: count,
            viewerHasReacted: viewerHasReacted
        )
    }
}

/// GitHub's "Bot" account marker.
struct PullRequestBotBadge: View {
    var body: some View {
        Text("Bot")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .overlay(Capsule().strokeBorder(Color.secondary.opacity(0.4), lineWidth: 1))
            .accessibilityLabel("Bot account")
    }
}

/// The tinted capsule pill comment surfaces put beside an author row or a thread
/// location: "Pending" for the viewer's unsubmitted comments, "Outdated" for
/// threads whose anchor has moved. Shared so both tabs draw the same shape.
struct PullRequestCommentBadge: View {
    let label: String
    let color: Color

    init(_ label: String, color: Color) {
        self.label = label
        self.color = color
    }

    var body: some View {
        Text(label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.14)))
            .foregroundStyle(color)
    }
}

/// Avatar, author text, and optional Bot pill, vertically centered, with a
/// caller-owned trailing slot (date, actions menu, ...).
struct PullRequestCommentAuthorRow<Trailing: View>: View {
    let login: String
    let avatarURL: URL?
    let isBot: Bool
    let avatarLoader: GitHubAvatarLoader?
    var authorFont: Font = .caption.weight(.medium)
    var authorIsProminent = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            if let avatarLoader {
                PullRequestAvatarView(login: login, url: avatarURL, loader: avatarLoader)
            }

            Text(login)
                .font(authorFont)
                .foregroundStyle(authorIsProminent ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))

            if isBot {
                PullRequestBotBadge()
            }

            trailing
        }
    }
}

/// The three-dot Edit/Delete comment menu shared by the Changes tab's thread rows
/// and the Overview timeline. Callers pass only the permitted actions; with both
/// `nil` the menu still renders, so gate mounting on having at least one action.
///
/// A third surface draws this menu — the transcript's review-proposal card — and it
/// is AppKit, so it cannot mount this view. It reads the statics below instead, and
/// they exist for exactly that: a glyph, hit target, or row title that drifts on one
/// surface stops reading as the same control. The chrome ones forward to
/// `AppOverflowMenuMetrics` so this menu cannot drift from the other surfaces wearing
/// the same control.
struct PullRequestCommentActionsMenu: View {
    static let glyphSymbolName = AppOverflowMenuMetrics.glyphSymbolName
    static let glyphPointSize = AppOverflowMenuMetrics.glyphPointSize
    static let hitTargetSize = AppOverflowMenuMetrics.hitTargetSize
    /// Both the hover tooltip and the VoiceOver name; the glyph carries no text.
    static let name = "Comment actions"
    static let editTitle = "Edit"
    static let editSymbolName = "pencil"
    static let deleteTitle = "Delete"
    static let deleteSymbolName = "trash"

    let onEdit: (() -> Void)?
    let onDelete: (() -> Void)?

    var body: some View {
        AppOverflowMenu(name: Self.name) {
            if let onEdit {
                AppOverflowMenuRow(
                    title: Self.editTitle,
                    systemImage: Self.editSymbolName,
                    action: onEdit
                )
            }
            if let onDelete {
                AppOverflowMenuRow(
                    title: Self.deleteTitle,
                    systemImage: Self.deleteSymbolName,
                    role: .destructive,
                    action: onDelete
                )
            }
        }
    }
}

/// The affordance that shows a comment on the diff it annotates: "Show in Changes" from
/// the Overview timeline, "Show in PR" from the transcript's review-proposal card.
/// Different words because they cross different distances, but one glyph and one tint,
/// because they do one thing.
///
/// The transcript's copy is AppKit and rebuilds the button by hand, so the parts it
/// cannot inherit live here — and what it cannot express as a static it borrows instead:
/// its hover drives `alphaValue` from `InlineActionButtonOpacity`, the same ramp the pane's
/// button brightens through. `AppAccentIcon` rather than a bare `Color.accentColor`:
/// this is a caption-sized glyph beside caption-sized text, the size at which the plain
/// accent washes out in light mode.
enum PullRequestCommentRevealAction {
    static let icon = ActionIcon.octicon(.fileDiff16)
    static let tint = AppAccentIcon.foreground
    static let tintNSColor = AppAccentIcon.foregroundNSColor
    static let overviewTitle = "Show in Changes"
    /// Abbreviated because it shares an author row with the avatar, the login, the
    /// "Proposed" pill, and the actions menu, on a card only as wide as the diff behind
    /// it — spelled out, it squeezed the author's name down to an ellipsis. "PR" is
    /// already this card's own vocabulary, from the "Open PR" button below it.
    static let transcriptTitle = "Show in PR"
    /// The tooltip and VoiceOver name, where there is room to say it properly.
    static let transcriptName = "Show this comment in the pull request"
}

/// Compact relative timestamp ("now", "5m", "3h", "2d", "3w", "1mo", "2y") whose
/// hover tooltip and accessibility label carry the absolute date and time. Shared
/// by the Overview timeline and the Changes tab's thread comments.
struct PullRequestTimestampLabel: View {
    let relative: String
    let absolute: String

    init(relative: String, absolute: String) {
        self.relative = relative
        self.absolute = absolute
    }

    init(date: Date, referenceDate: Date) {
        self.init(
            relative: compactRelativeAge(from: date, relativeTo: referenceDate),
            absolute: PullRequestTimestampFormatting.absoluteString(for: date)
        )
    }

    var body: some View {
        Text(relative)
            .font(.caption)
            .foregroundStyle(.secondary)
            .help(absolute)
            .accessibilityLabel(absolute)
    }
}

@MainActor
enum PullRequestTimestampFormatting {
    /// One cached formatter: building a `DateFormatter` (or resolving a
    /// `FormatStyle`) per render is the expensive part of date formatting, and
    /// the Changes tab's lazily recycled rows re-render on every scroll-back-in.
    private static let absoluteFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func absoluteString(for date: Date) -> String {
        absoluteFormatter.string(from: date)
    }
}

/// The collapsed-resolved header shared by the Changes tab's thread rows and the
/// Overview timeline's threads: chevron, "Resolved", and the comment count.
/// Resolved threads collapse their whole conversation — replies included — behind
/// it; tapping toggles the caller's manual-expansion state.
struct PullRequestResolvedThreadHeader: View {
    let commentCount: Int
    @Binding var isExpanded: Bool

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @State private var isHovering = false

    /// Hovering brightens the whole row rather than going through
    /// `inlineActionButtonStyle(foregroundColor:)`, which paints one tint: this label carries
    /// three at once — a secondary chevron, a green "Resolved", a secondary count — and a single
    /// foreground colour would flatten them. The ramp is still the shared one, Increase Contrast
    /// included, so this row and the Reply/Resolve pair below it lift by the same amount.
    private var rowOpacity: Double {
        isHovering
            ? InlineActionButtonOpacity.active
            : InlineActionButtonOpacity.resting(increasesContrast: colorSchemeContrast == .increased)
    }

    var body: some View {
        Button {
            isExpanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))

                Text("Resolved")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)

                Text("\(commentCount) comment\(commentCount == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)
            }
            .opacity(rowOpacity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) {
                isHovering = hovering
            }
        }
        .accessibilityLabel("Resolved conversation, \(commentCount) comments")
        .accessibilityHint(isExpanded ? "Collapses the conversation" : "Expands the conversation")
    }
}

/// Reply and Resolve/Unresolve, GitHub style — the thread footer shared by the
/// Changes tab's thread rows and the Overview timeline's threads. Both actions
/// need a submitted thread: replies attach to the root remote comment and
/// resolution needs the thread's node id, so callers gate through the flags.
struct PullRequestThreadActionsFooter: View {
    let isResolved: Bool
    let canReply: Bool
    let canResolve: Bool
    let onReply: () -> Void
    let onToggleResolved: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            if canReply {
                Button(action: onReply) {
                    ActionButtonLabel(
                        title: "Reply",
                        icon: .octicon(.reply16),
                        scale: .inline
                    )
                }
                .inlineActionButtonStyle(foregroundColor: .accentColor)
                .font(.caption)
                .accessibilityLabel("Reply to thread")
            }

            if canResolve {
                Button(action: onToggleResolved) {
                    // Both states stay in the circle family so they read as one
                    // toggle, and so neither is mistaken for Reply's bare arrow.
                    ActionButtonLabel(
                        title: isResolved ? "Unresolve conversation" : "Resolve conversation",
                        icon: isResolved
                            ? .system("arrow.uturn.backward.circle")
                            : .octicon(.checkCircle16),
                        scale: .inline
                    )
                }
                .inlineActionButtonStyle(foregroundColor: .secondary)
                .font(.caption)
            }

            Spacer(minLength: 0)
        }
        .padding(.top, 2)
    }
}

/// Sanitized comment body plus its reaction bar; the reaction bar renders only for
/// comments with a GraphQL node id (pending local comments have none).
struct PullRequestCommentBody: View {
    let markdown: String
    let nodeID: String?
    let reactions: [PullRequestCommentReaction]
    let viewModel: PullRequestsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            let sanitized = PullRequestMarkdown.sanitized(markdown)
            if !sanitized.isEmpty {
                AppMarkdownText(markdown: sanitized)
            }

            if let nodeID {
                CommentReactionBar(
                    reactions: reactions.map(\.asCommentReaction),
                    options: PullRequestReactionContent.pickerOptions,
                    onToggle: { content in
                        viewModel.toggleReaction(
                            subjectID: nodeID,
                            content: content,
                            viewerHasReacted: reactions.first { $0.content.rawValue == content }?
                                .viewerHasReacted ?? false
                        )
                    }
                )
            }
        }
    }
}
