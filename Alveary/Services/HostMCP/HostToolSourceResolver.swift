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
    case sourceHarnessMismatch
}

@MainActor
enum HostToolSourceResolver {
    /// Resolves the calling conversation from `AgentHostToolCallContext`.
    ///
    /// A caller Alveary cannot place — a vanished conversation, a draft or archived thread, or a
    /// process whose harness disagrees with the stored one — gets no host state at all. Feature
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
        if let storedHarnessID = conversation.harness,
           storedHarnessID != context.harnessId.rawValue {
            throw HostToolSourceError.sourceHarnessMismatch
        }
        return HostToolCallSource(conversation: conversation, thread: thread)
    }
}
