import AgentCLIKit
import Foundation
import SwiftData

/// The conversation and thread a host tool call came from, resolved from trusted runtime
/// context rather than anything the model supplied.
struct HostToolCallSource {
    let conversation: Conversation
    let thread: AgentThread
}

enum HostToolSourceError: Error, Equatable, Sendable {
    case sourceConversationUnavailable
    case sourceProviderMismatch
}

@MainActor
enum HostToolSourceResolver {
    /// Resolves the calling conversation from `AgentHostToolCallContext`.
    ///
    /// A caller Alveary cannot place — a vanished conversation, a draft or archived thread, or a
    /// process whose provider disagrees with the stored one — gets no host state at all. Feature
    /// eligibility layers on top of this; it never replaces it.
    static func resolveSource(
        context: AgentCLIKit.AgentHostToolCallContext,
        in modelContext: ModelContext
    ) throws -> HostToolCallSource {
        guard let conversation = modelContext.resolveConversation(
            conversationID: context.conversationId.rawValue
        ), let thread = conversation.thread,
           !thread.isDraft,
           thread.archivedAt == nil else {
            throw HostToolSourceError.sourceConversationUnavailable
        }
        if let storedProviderID = conversation.provider,
           storedProviderID != context.providerId.rawValue {
            throw HostToolSourceError.sourceProviderMismatch
        }
        return HostToolCallSource(conversation: conversation, thread: thread)
    }
}
