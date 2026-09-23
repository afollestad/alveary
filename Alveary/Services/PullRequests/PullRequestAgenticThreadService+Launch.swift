import Foundation
import SwiftData

/// A created or reused task, available before linking and harness dispatch finish.
struct PullRequestAgenticThreadStart {
    /// The task's sole-main-conversation id, also used by host thread tools.
    let conversationID: String
    /// Links, settles any checkout, and dispatches work. Completion confirms startup, never review completion.
    let dispatch: Task<PullRequestAgenticDispatchOutcome, Error>
    let destination: PullRequestAgenticThreadDestination

    init(
        conversationID: String,
        dispatch: Task<PullRequestAgenticDispatchOutcome, Error>,
        destination: PullRequestAgenticThreadDestination? = nil
    ) {
        self.conversationID = conversationID
        self.dispatch = dispatch
        self.destination = destination ?? PullRequestAgenticThreadDestination(
            conversationID: conversationID, name: "Review", reviewMode: .singleAgent, disposition: .created
        )
    }
}

/// Linking can fail after a successful launch; only a thrown dispatch means no work started.
struct PullRequestAgenticDispatchOutcome: Equatable {
    /// A failed link, already localized, for the caller's toast. Nil when the link landed.
    let linkFailure: String?
}

struct PullRequestAgenticThreadDestination: Equatable, Sendable {
    enum Disposition: String, Sendable {
        case created, existing
    }

    let conversationID: String
    let name: String
    let reviewMode: PullRequestReviewMode
    let disposition: Disposition
    var runID: String?
    var phase: ReviewTeamRun.Phase?
}

struct PullRequestAgenticThreadAuthorization {
    let validateSource: @MainActor () throws -> Void
    let checkpoint: @MainActor (PullRequestAgenticThreadDestination) throws -> Void
}

/// A task already exists when its checkpoint or deferred dispatch fails; callers must retain its identity.
struct PullRequestAgenticThreadLaunchError: LocalizedError {
    let destination: PullRequestAgenticThreadDestination
    let underlying: any Error

    var errorDescription: String? { underlying.localizedDescription }
}

/// Reserves each PR route across UI and host-tool callers, including the suspension before a task exists.
extension PullRequestAgenticThreadService {
    func start(
        kind: Kind,
        identifier: PullRequestIdentifier,
        url: URL,
        knownDetail: PullRequestDetail? = nil,
        knownSummary: PullRequestSummary? = nil,
        preferredProjectID: PersistentIdentifier? = nil,
        validateSource: @escaping @MainActor () throws -> Void = {},
        checkpoint: @escaping @MainActor (PullRequestAgenticThreadDestination) throws -> Void = { _ in }
    ) async throws -> PullRequestAgenticThreadStart {
        try Task.checkCancellation()
        try validateSource()
        let key = PullRequestAgenticThreadActivity.Key(identifier: identifier, kind: kind)
        if let pending = pendingLaunches[key] {
            return try reusedStart(try await pending.wait(), validateSource: validateSource, checkpoint: checkpoint)
        }
        if let active = activeLaunches[key], activity.isWorking(identifier, kind: kind),
           let thread = lifecycleService.modelContext.resolveConversation(conversationID: active.conversationID)?.thread,
           thread.archivedAt == nil {
            return try reusedStart(active, validateSource: validateSource, checkpoint: checkpoint)
        }
        if let existing = try unfinishedReviewStart(kind: kind, identifier: identifier, checkpoint: checkpoint) {
            return existing
        }

        let settings = settingsService.current
        let pending = PullRequestLaunchReservation()
        pendingLaunches[key] = pending
        activity.begin(identifier, kind: kind)
        do {
            let result = try await createLaunch(
                kind: kind, identifier: identifier, url: url, knownDetail: knownDetail,
                knownSummary: knownSummary, preferredProjectID: preferredProjectID, settings: settings,
                authorization: PullRequestAgenticThreadAuthorization(validateSource: validateSource, checkpoint: checkpoint)
            )
            pendingLaunches.removeValue(forKey: key)
            activeLaunches[key] = result
            pending.resolve(.success(result))
            return result
        } catch {
            pendingLaunches.removeValue(forKey: key)
            activity.endPending(identifier, kind: kind)
            pending.resolve(.failure(error))
            throw error
        }
    }

    func destination(
        conversationID: String,
        disposition: PullRequestAgenticThreadDestination.Disposition
    ) throws -> PullRequestAgenticThreadDestination {
        guard let conversation = lifecycleService.modelContext.resolveConversation(conversationID: conversationID),
              let thread = conversation.thread else { throw StartError.conversationMissing }
        let run = try conversation.collectiveReviewRun()
        let accepted = acceptedLaunches[conversationID]?.destination
        return PullRequestAgenticThreadDestination(
            conversationID: conversationID, name: thread.displayName(),
            reviewMode: run == nil ? accepted?.reviewMode ?? .singleAgent : .reviewTeam,
            disposition: disposition, runID: run?.id, phase: run?.phase
        )
    }

    func dispatch(conversationID: String) -> Task<PullRequestAgenticDispatchOutcome, Error>? {
        acceptedLaunches[conversationID]?.dispatch
    }

    /// Checkpoint the created identity before scheduling any network work or harness turn.
    func preparedStart(
        destination target: PullRequestAgenticThreadDestination,
        identifier: PullRequestIdentifier, kind: Kind,
        checkpoint: @MainActor (PullRequestAgenticThreadDestination) throws -> Void,
        operation: @escaping @MainActor () async throws -> PullRequestAgenticDispatchOutcome
    ) throws -> PullRequestAgenticThreadStart {
        let conversationID = target.conversationID
        do {
            try checkpoint(target)
        } catch {
            recordLaunchFailure(error, destination: target)
            throw PullRequestAgenticThreadLaunchError(destination: target, underlying: error)
        }
        activity.attach(conversationID: conversationID, identifier: identifier, kind: kind)
        let dispatch = Task { [self] in
            defer { retainCompletedLaunch(conversationID) }
            do {
                let outcome = try await operation()
                activity.armStartupGrace(identifier, kind: kind)
                return outcome
            } catch {
                activity.end(identifier, kind: kind, conversationID: conversationID)
                recordLaunchFailure(error, destination: target)
                throw PullRequestAgenticThreadLaunchError(destination: target, underlying: error)
            }
        }
        let start = PullRequestAgenticThreadStart(conversationID: conversationID, dispatch: dispatch, destination: target)
        activeLaunches[PullRequestAgenticThreadActivity.Key(identifier: identifier, kind: kind)] = start
        acceptedLaunches[conversationID] = start
        return start
    }

    func unfinishedReviewStart(
        kind: Kind, identifier: PullRequestIdentifier,
        checkpoint: @MainActor (PullRequestAgenticThreadDestination) throws -> Void
    ) throws -> PullRequestAgenticThreadStart? {
        guard kind == .review, let run = try reviewTeamCoordinator?.unfinishedReview(for: identifier) else { return nil }
        let target = try destination(conversationID: run.conversationID, disposition: .existing)
        try checkpoint(target)
        activity.endPending(identifier, kind: kind)
        activity.setCollectivePhase(run.phase, identifier: identifier, conversationID: run.conversationID)
        return PullRequestAgenticThreadStart(
            conversationID: target.conversationID,
            dispatch: acceptedLaunches[target.conversationID]?.dispatch ?? Task { PullRequestAgenticDispatchOutcome(linkFailure: nil) },
            destination: target
        )
    }

    private func reusedStart(
        _ start: PullRequestAgenticThreadStart,
        validateSource: @MainActor () throws -> Void,
        checkpoint: @MainActor (PullRequestAgenticThreadDestination) throws -> Void
    ) throws -> PullRequestAgenticThreadStart {
        try Task.checkCancellation()
        try validateSource()
        let target = try destination(conversationID: start.conversationID, disposition: .existing)
        try checkpoint(target)
        return PullRequestAgenticThreadStart(conversationID: target.conversationID, dispatch: start.dispatch, destination: target)
    }

    /// Completed startup tasks only serve receipt recovery; persisted review runs outlive this bounded cache.
    private func retainCompletedLaunch(_ conversationID: String) {
        completedLaunchOrder.append(conversationID)
        while completedLaunchOrder.count > 128 {
            let expired = completedLaunchOrder.removeFirst()
            acceptedLaunches.removeValue(forKey: expired)
            for (key, start) in activeLaunches where start.conversationID == expired && !activity.isWorking(key.identifier, kind: key.kind) {
                activeLaunches.removeValue(forKey: key)
            }
        }
    }

    /// A launch that fails after its task exists runs no turn, so no terminal boundary will paint the row;
    /// this records the durable failure beside the error row instead. Only before initial setup completes:
    /// the team path awaits its link while the new thread is already visible, and a turn the user started
    /// there owns the flag — writing it mid-turn would outrank that turn's live spinner.
    private func recordLaunchFailure(_ error: any Error, destination: PullRequestAgenticThreadDestination) {
        let context = lifecycleService.modelContext
        guard let conversation = context.resolveConversation(conversationID: destination.conversationID) else { return }
        context.insert(ConversationEventRecord(
            conversationId: conversation.id, type: ConversationEventRecord.errorType,
            content: "Review could not start: \(error.localizedDescription)", isError: true, conversation: conversation
        ))
        if conversation.thread?.hasCompletedInitialSetup == false {
            conversation.lastTurnFailedAt = .now
        }
        try? context.save()
    }
}

/// Waiters share a launch without adding a task hop between the creator's insertion and its return.
@MainActor
final class PullRequestLaunchReservation {
    func wait() async throws -> PullRequestAgenticThreadStart {
        try Task.checkCancellation()
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if let result {
                    continuation.resume(with: result)
                } else {
                    waiters[id] = continuation
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func resolve(_ result: Result<PullRequestAgenticThreadStart, any Error>) {
        self.result = result
        let waiting = waiters.values
        waiters.removeAll()
        for waiter in waiting { waiter.resume(with: result) }
    }

    private var result: Result<PullRequestAgenticThreadStart, any Error>?
    private var waiters: [UUID: CheckedContinuation<PullRequestAgenticThreadStart, any Error>] = [:]
}
