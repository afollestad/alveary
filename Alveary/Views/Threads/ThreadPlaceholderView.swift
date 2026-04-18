import SwiftUI

struct ThreadPlaceholderView: View {
    let thread: AgentThread
    @Bindable var appState: AppState

    private var conversations: [Conversation] {
        thread.conversations.sorted {
            if $0.displayOrder != $1.displayOrder {
                return $0.displayOrder < $1.displayOrder
            }
            if $0.isMain != $1.isMain {
                return $0.isMain && !$1.isMain
            }
            return $0.id < $1.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(thread.name)
                    .font(.largeTitle.weight(.semibold))

                Text(thread.project?.name ?? "Project")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            if !conversations.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Conversations")
                        .font(.headline)

                    ForEach(conversations) { conversation in
                        Button {
                            appState.selectConversation(conversation, in: thread)
                        } label: {
                            HStack(spacing: 12) {
                                Image(
                                    systemName: conversation.isMain
                                        ? "bubble.left.and.bubble.right.fill"
                                        : "bubble.left.fill"
                                )
                                    .foregroundStyle(conversation.isMain ? Color.accentColor : Color.secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(conversation.displayName())
                                        .font(.headline)
                                        .foregroundStyle(.primary)

                                    Text(conversation.id)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer()

                                if appState.selectedConversation(in: thread)?.persistentModelID == conversation.persistentModelID {
                                    Text("Selected")
                                        .font(.caption.weight(.semibold))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(Capsule().fill(AppSelectionStyle.rowFill))
                                }
                            }
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(Color.secondary.opacity(0.08))
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            EmptyStateView(
                icon: "bubble.left.and.text.bubble.right.fill",
                heading: "Conversation workspace coming next",
                subtext: "This shell now routes the sidebar, project settings, skills, MCP, and diff viewer. "
                    + "The thread chat surface is the next Phase 6 slice to land.",
                actions: []
            )
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}
