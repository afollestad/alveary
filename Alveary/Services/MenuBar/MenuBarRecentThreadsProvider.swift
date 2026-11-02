import Foundation
import SwiftData

/// One status-menu row: the title to show and the conversation id the routers take.
struct MenuBarRecentThread: Equatable, Identifiable, Sendable {
    let conversationID: String
    let title: String

    var id: String { conversationID }
}

/// Supplies the status menu's recent threads.
///
/// Openability is `AgentThread.isListableHostToolThread` and recency is `AgentThreadOrdering`;
/// both already answer "threads a user can be sent to, most recently touched first", so this
/// holds no predicate of its own.
@MainActor
final class MenuBarRecentThreadsProvider {
    nonisolated static let defaultLimit = 5

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func recentThreads(limit: Int = defaultLimit) -> [MenuBarRecentThread] {
        guard limit > 0 else {
            return []
        }
        let threads = (try? modelContext.fetch(FetchDescriptor<AgentThread>())) ?? []
        return AgentThreadOrdering.sorted(threads.filter(\.isListableHostToolThread))
            .prefix(limit)
            .compactMap { thread in
                guard let conversation = thread.soleMainConversation else {
                    return nil
                }
                return MenuBarRecentThread(
                    conversationID: conversation.id,
                    title: MenuBarItemTitle.truncated(thread.displayName())
                )
            }
    }
}
