import Foundation

struct ConversationControllerKey: Hashable, Sendable {
    let conversationID: String

    init(conversationID: String) {
        self.conversationID = conversationID
    }

    @MainActor
    init(conversation: Conversation) {
        self.init(conversationID: conversation.id)
    }
}

struct ConversationControllerTurn: Hashable, Sendable {
    let epoch: UInt64
}

struct ConversationControllerOutcome: Equatable, Sendable {
    enum State: Equatable, Sendable {
        case active
        case waitingForApproval(interactionID: String?)
        case waitingForQuestion(interactionID: String?)
        case terminal(TerminalResult)
        case interrupted

        var isTerminal: Bool {
            switch self {
            case .terminal, .interrupted:
                return true
            case .active, .waitingForApproval, .waitingForQuestion:
                return false
            }
        }
    }

    enum TerminalResult: Equatable, Sendable {
        case succeeded
        case failed(message: String?)
    }

    let turn: ConversationControllerTurn
    let state: State
}

struct ConversationControllerFlushFailure: Equatable, Sendable {
    let key: ConversationControllerKey
    let message: String
}

enum ConversationControllerLeaseKind: Sendable {
    case view
    case background
}

@MainActor
final class ConversationControllerLease {
    let key: ConversationControllerKey
    let kind: ConversationControllerLeaseKind
    let viewModel: ConversationViewModel

    private let setActive: (Bool) -> Void
    private let releaseLease: () -> Void
    private let makeOutcomeStream: () -> AsyncStream<ConversationControllerOutcome>
    private var isActive = false
    private var isReleased = false

    init(
        key: ConversationControllerKey,
        kind: ConversationControllerLeaseKind,
        viewModel: ConversationViewModel,
        setActive: @escaping (Bool) -> Void,
        releaseLease: @escaping () -> Void,
        makeOutcomeStream: @escaping () -> AsyncStream<ConversationControllerOutcome>
    ) {
        self.key = key
        self.kind = kind
        self.viewModel = viewModel
        self.setActive = setActive
        self.releaseLease = releaseLease
        self.makeOutcomeStream = makeOutcomeStream
    }

    func activate() {
        guard !isReleased, !isActive else {
            return
        }
        isActive = true
        setActive(true)
    }

    func deactivate() {
        guard !isReleased, isActive else {
            return
        }
        isActive = false
        setActive(false)
    }

    func outcomes() -> AsyncStream<ConversationControllerOutcome> {
        makeOutcomeStream()
    }

    func release() {
        guard !isReleased else {
            return
        }
        deactivate()
        isReleased = true
        releaseLease()
    }

    isolated deinit {
        release()
    }
}

@MainActor
protocol ConversationControllerRegistry: AnyObject {
    func makeViewLease(for conversation: Conversation) -> ConversationControllerLease
    func makeBackgroundLease(for conversation: Conversation) -> ConversationControllerLease
    func controller(for key: ConversationControllerKey) -> ConversationViewModel?
    func outcomes(for key: ConversationControllerKey) -> AsyncStream<ConversationControllerOutcome>
    func flushForTermination() -> [ConversationControllerFlushFailure]
    func invalidate(for key: ConversationControllerKey)
    func invalidateAll()
}
