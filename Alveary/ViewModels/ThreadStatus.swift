import Foundation

enum ThreadStatus: Sendable, Equatable {
    case busy
    case waitingForUser
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
        case .waitingForUser:
            return .waitingForUser
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
        var isWaitingForUser = false
        var hasUnread = false

        for conversation in conversations {
            let signal = runtimeFor(conversation)
            if signal == .busy {
                return .busy
            }
            if signal == .waitingForUser {
                isWaitingForUser = true
            }
            if signal == .error {
                hasError = true
            }
            if conversation.isUnread {
                hasUnread = true
            }
        }

        if isWaitingForUser {
            return .waitingForUser
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
