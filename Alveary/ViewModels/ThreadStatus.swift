import Foundation

enum ThreadStatus: Sendable, Equatable {
    case busy
    case unread
    case stopped
    case error
    case archived
}

extension Conversation {
    @MainActor
    func displayStatus(runtime: ActivitySignal) -> ThreadStatus {
        if thread?.archivedAt != nil {
            return .archived
        }

        switch runtime {
        case .busy:
            return .busy
        case .error:
            return .error
        case .idle, .stopped, .neutral:
            return isUnread ? .unread : .stopped
        }
    }
}

extension AgentThread {
    @MainActor
    func displayStatus(runtimeFor: (Conversation) -> ActivitySignal) -> ThreadStatus {
        if archivedAt != nil {
            return .archived
        }

        var hasError = false
        var hasUnread = false

        for conversation in conversations {
            let signal = runtimeFor(conversation)
            if signal == .busy {
                return .busy
            }
            if signal == .error {
                hasError = true
            }
            if conversation.isUnread {
                hasUnread = true
            }
        }

        if hasError {
            return .error
        }
        if hasUnread {
            return .unread
        }
        return .stopped
    }
}
