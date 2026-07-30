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
