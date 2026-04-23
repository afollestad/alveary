import SwiftData
import SwiftUI

struct ThreadPlaceholderView: View {
    let thread: AgentThread
    @Bindable var appState: AppState
    @Environment(\.modelContext) private var modelContext

    private var liveThread: AgentThread? {
        modelContext.resolveThread(id: thread.persistentModelID)
    }

    private func conversations(for thread: AgentThread) -> [Conversation] {
        let threadID = thread.persistentModelID
        let descriptor = FetchDescriptor<Conversation>(
            predicate: #Predicate { conversation in
                conversation.thread?.persistentModelID == threadID
            }
        )
        let conversations = (try? modelContext.fetch(descriptor)) ?? []
        return conversations.sorted {
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
        if let liveThread {
            content(for: liveThread, conversations: conversations(for: liveThread))
        }
    }

    private func content(for thread: AgentThread, conversations: [Conversation]) -> some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text(thread.name)
                    .font(.largeTitle.weight(.semibold))

                Text(thread.project?.name ?? "Project")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            conversationsSection(thread: thread, conversations: conversations)

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

    @ViewBuilder
    private func conversationsSection(thread: AgentThread, conversations: [Conversation]) -> some View {
        if !conversations.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Conversations")
                    .font(.headline)

                ForEach(conversations) { conversation in
                    conversationRow(thread: thread, conversation: conversation, conversations: conversations)
                }
            }
        }
    }

    private func conversationRow(
        thread: AgentThread,
        conversation: Conversation,
        conversations: [Conversation]
    ) -> some View {
        Button {
            appState.selectConversation(conversation, in: thread)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: conversation.isMain ? "bubble.left.and.bubble.right.fill" : "bubble.left.fill")
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

                if appState.selectedConversation(in: thread, conversations: conversations)?.persistentModelID == conversation.persistentModelID {
                    Text("Selected")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(AppAccentFill.primary))
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
