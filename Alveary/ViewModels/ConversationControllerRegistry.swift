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
    private let finalizeDeferredLease: (DeferredControllerReleaseAction) async throws -> Void
    private let makeOutcomeStream: () -> AsyncStream<ConversationControllerOutcome>
    private let defersAutomaticSuspension: Bool
    private var isActive = false
    private var isReleased = false
    private var deferredFinalizationTask: Task<Void, Error>?

    init(
        key: ConversationControllerKey,
        kind: ConversationControllerLeaseKind,
        viewModel: ConversationViewModel,
        defersAutomaticSuspension: Bool,
        setActive: @escaping (Bool) -> Void,
        releaseLease: @escaping () -> Void,
        finalizeDeferredLease: @escaping (DeferredControllerReleaseAction) async throws -> Void,
        makeOutcomeStream: @escaping () -> AsyncStream<ConversationControllerOutcome>
    ) {
        self.key = key
        self.kind = kind
        self.viewModel = viewModel
        self.defersAutomaticSuspension = defersAutomaticSuspension
        self.setActive = setActive
        self.releaseLease = releaseLease
        self.finalizeDeferredLease = finalizeDeferredLease
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

    /// Flushes and suspends a deferred background controller before releasing its lease.
    /// `beforeRelease` runs after suspension while the background lifecycle is still retained,
    /// allowing follow-up work to retain the controller before the deferred lease is removed.
    /// Concurrent callers join the same registry-owned finalization.
    func finalizeDeferredSuspension(
        beforeRelease: @escaping @MainActor () throws -> Void = {}
    ) async throws {
        guard !isReleased else {
            return
        }
        precondition(defersAutomaticSuspension, "Only deferred background leases require explicit finalization")

        if let deferredFinalizationTask {
            try await deferredFinalizationTask.value
            self.deferredFinalizationTask = nil
            isActive = false
            isReleased = true
            return
        }

        let finalizeDeferredLease = self.finalizeDeferredLease
        let releaseAction = DeferredControllerReleaseAction(beforeRelease)
        let task = Task { @MainActor in
            try await finalizeDeferredLease(releaseAction)
        }
        deferredFinalizationTask = task
        do {
            try await task.value
            deferredFinalizationTask = nil
            isActive = false
            isReleased = true
        } catch {
            deferredFinalizationTask = nil
            throw error
        }
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
final class DeferredControllerReleaseAction {
    private let action: @MainActor () throws -> Void

    init(_ action: @escaping @MainActor () throws -> Void) {
        self.action = action
    }

    func perform() throws {
        try action()
    }
}

@MainActor
protocol ConversationControllerRegistry: AnyObject {
    func makeViewLease(for conversation: Conversation) -> ConversationControllerLease
    func makeBackgroundLease(for conversation: Conversation) -> ConversationControllerLease
    func makeBackgroundLease(
        for conversation: Conversation,
        defersAutomaticSuspension: Bool
    ) -> ConversationControllerLease
    func controller(for key: ConversationControllerKey) -> ConversationViewModel?
    func outcomes(for key: ConversationControllerKey) -> AsyncStream<ConversationControllerOutcome>
    func flushForTermination() -> [ConversationControllerFlushFailure]
    func invalidate(for key: ConversationControllerKey)
    func invalidateAll()
}

extension ConversationControllerRegistry {
    func reconcileScheduledTaskTerminalState(conversationID: String) {
        controller(for: ConversationControllerKey(conversationID: conversationID))?
            .reconcileScheduledTaskTerminalState()
    }
}
