import Foundation
import Observation
import SwiftData

/// Owns collective work independently of windows and provider turns. Only a persisted active generation may stage.
@MainActor @Observable
final class PullRequestReviewTeamCoordinator {
    private(set) var runs: [String: ReviewTeamRun] = [:]
    let modelContext: ModelContext
    let service: any PullRequestsService
    let worker: any PullRequestReviewWorkerExecuting
    let packets: ReviewPacketStore
    let staging: PullRequestCollectiveReviewStagingService
    let activity: PullRequestAgenticThreadActivity
    let resolver: PullRequestReviewTeamResolver
    let historyStore: ReviewTeamHistoryStore?
    let cancellationStore: ReviewTeamCancellationStore
    let commitSave: (ModelContext) throws -> Void
    @ObservationIgnored private var tasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []
    @ObservationIgnored private var didRecover = false

    init(
        modelContext: ModelContext, service: any PullRequestsService,
        worker: any PullRequestReviewWorkerExecuting, packets: ReviewPacketStore,
        staging: PullRequestCollectiveReviewStagingService, activity: PullRequestAgenticThreadActivity,
        resolver: PullRequestReviewTeamResolver,
        cancellationStore: ReviewTeamCancellationStore,
        historyStore: ReviewTeamHistoryStore? = nil,
        commitSave: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.modelContext = modelContext
        self.service = service
        self.worker = worker
        self.packets = packets
        self.staging = staging
        self.activity = activity
        self.resolver = resolver
        self.historyStore = historyStore
        self.cancellationStore = cancellationStore
        self.commitSave = commitSave
        observeActions()
    }

    deinit {
        MainActor.assumeIsolated {
            for observer in observers { NotificationCenter.default.removeObserver(observer) }
        }
    }

    var workingConversationIDs: Set<String> {
        Set(runs.values.filter { $0.phase.isWorking }.map(\.conversationID))
    }

    #if DEBUG
    /// Capture before cancellation removes the dictionary entry so tests can await late-result consumption.
    func scheduledTaskForTesting(conversationID: String) -> Task<Void, Never>? {
        tasks[conversationID]
    }
    #endif

    func preflight(settings: AppSettings) async throws -> [ReviewWorkerConfiguration] {
        let team = try await resolver.resolve(settings: settings)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for configuration in team {
                group.addTask { [worker] in try await worker.preflight(configuration) }
            }
            try await group.waitForAll()
        }
        return team
    }

    func begin(
        conversationID: String, identifier: PullRequestIdentifier, url: URL,
        team: [ReviewWorkerConfiguration], criteria: String
    ) throws {
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID),
              let thread = conversation.thread,
              thread.archivedAt == nil else {
            throw ReviewTeamError.missingConversation
        }
        guard try !hasUnfinishedReview(for: identifier) else {
            throw ReviewTeamError.invalidOutput("A team review is already running for this pull request.")
        }
        let snapshot = try staging.snapshot(for: identifier, editState: currentEditState(for: identifier))
        let run = ReviewTeamRun(
            payloadVersion: 1, id: UUID().uuidString, proposalID: UUID().uuidString,
            conversationID: conversationID, identifier: identifier, url: url, team: team, criteria: criteria,
            priorProposal: snapshot, createdAt: .now, generation: 0, phase: .preparing,
            inspections: [:], voteReports: [:], accepted: [], attempts: [:], failures: [:], supersededProposalIDs: [], history: []
        )
        try persist(run)
        schedule(run)
    }

    func cancel(conversationID: String, runID: String? = nil, generation: Int? = nil) {
        guard var run = runs[conversationID], run.phase.isUnfinished,
              runID == nil || runID == run.id, generation == nil || generation == run.generation else { return }
        run.generation += 1
        run.phase = .cancelled
        run.error = nil
        run.pausedPhase = nil
        run.finishRunningAttempts(as: .cancelled)
        let hasReceipt = (try? cancellationStore.record(runID: run.id)) != nil
        // Save before cancelling: a callback already queued on MainActor must observe a stale generation.
        do {
            try persist(run)
            try? cancellationStore.remove(runID: run.id)
        } catch {
            run.error = hasReceipt
                ? "Review cancelled. Task history could not be saved; cancellation will be restored after relaunch."
                : "Workers stopped, but cancellation could not be saved. This review may resume after relaunch."
            if !hasReceipt { run.phase = .failed; run.requiresNewRun = true }
            runs[conversationID] = run
            publish(run)
        }
        tasks.removeValue(forKey: conversationID)?.cancel()
        Task { [worker, packets] in
            await worker.cancel(runID: run.id)
            try? await packets.remove(runID: run.id)
        }
    }

    func retry(conversationID: String) {
        guard let thread = modelContext.resolveConversation(conversationID: conversationID)?.thread,
              thread.archivedAt == nil,
              var run = runs[conversationID], run.requiresNewRun != true,
              run.phase == .failed || run.phase == .interrupted else { return }
        guard (try? hasUnfinishedReview(for: run.identifier, excludingConversationID: conversationID)) == false else { return }
        run.generation += 1
        run.phase = .preparing
        run.error = nil
        run.retryPhase = nil
        run.pausedPhase = nil
        run.continuedPhases = nil
        run.attempts = [:]
        run.failures = [:]
        do {
            try persist(run)
            schedule(run)
        } catch { runs[conversationID]?.error = error.localizedDescription }
    }

    /// Runs once per app lifetime; staged receipts are terminal even after the user dismisses their proposal.
    func recover() {
        guard !didRecover else { return }
        didRecover = true
        pruneHistory()
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.pullRequestReviewRunJSON != nil })
        guard let conversations = try? modelContext.fetch(descriptor) else { return }
        for conversation in conversations {
            guard tasks[conversation.id] == nil else { continue }
            guard var run = try? conversation.collectiveReviewRun() else { continue }
            runs[run.conversationID] = run
            repairSupersededOutcome(run)
            if restoreCancellationIfNeeded(run) { continue }
            guard conversation.thread?.archivedAt == nil else {
                cancel(conversationID: run.conversationID)
                continue
            }
            if run.phase == .awaitingDecision {
                publish(run)
                continue
            }
            guard run.phase.isWorking || run.phase == .interrupted else {
                try? cancellationStore.remove(runID: run.id)
                Task { [packets, runID = run.id] in try? await packets.remove(runID: runID) }
                continue
            }
            run.generation += 1
            run.phase = .preparing
            run.finishRunningAttempts(as: .interrupted)
            do { try persist(run); schedule(run) } catch { runs[run.conversationID]?.error = error.localizedDescription }
        }
    }

    /// Synchronous persistence is required while AppDelegate still owns the main actor at termination.
    func prepareForTermination() {
        for var run in Array(runs.values) where run.phase.isWorking {
            run.generation += 1
            run.phase = .interrupted
            run.finishRunningAttempts(as: .interrupted)
            try? persist(run)
            tasks.removeValue(forKey: run.conversationID)?.cancel()
        }
    }

    func requireActive(_ conversationID: String, generation: Int) throws -> ReviewTeamRun {
        try Task.checkCancellation()
        guard let conversation = modelContext.resolveConversation(conversationID: conversationID),
              let thread = conversation.thread, thread.archivedAt == nil,
              let run = try conversation.collectiveReviewRun(),
              run.generation == generation, run.phase.isWorking,
              runs[conversationID]?.generation == generation else { throw ReviewTeamError.cancelled }
        return run
    }

    func update(_ conversationID: String, generation: Int, _ change: (inout ReviewTeamRun) -> Void) throws {
        var run = try requireActive(conversationID, generation: generation)
        change(&run)
        try persist(run)
    }

    func persist(_ run: ReviewTeamRun) throws {
        if modelContext.hasChanges { try commitSave(modelContext) }
        guard let conversation = modelContext.resolveConversation(conversationID: run.conversationID) else {
            throw ReviewTeamError.missingConversation
        }
        let priorJSON = conversation.pullRequestReviewRunJSON
        let priorEvents = conversation.events
        let progressEvent = priorEvents.first { $0.id == "collective-review-run:\(run.id)" }
        let priorContent = progressEvent?.content
        do {
            try conversation.storeCollectiveReviewRun(run)
            try storeProgressEvent(run, conversation: conversation)
            try commitSave(modelContext)
        } catch {
            // Restore observed references as well as the store, matching proposal-swap rollback.
            modelContext.processPendingChanges()
            conversation.pullRequestReviewRunJSON = priorJSON
            conversation.events = priorEvents
            progressEvent?.content = priorContent
            modelContext.processPendingChanges()
            modelContext.rollback()
            throw error
        }
        didPersist(run)
    }

    func didPersist(_ run: ReviewTeamRun) {
        runs[run.conversationID] = run
        publish(run)
    }

    func forgetRun(conversationID: String) {
        runs.removeValue(forKey: conversationID)
    }

    func storeProgressEvent(_ run: ReviewTeamRun, conversation: Conversation) throws {
        let eventID = "collective-review-run:\(run.id)"
        let content = try ReviewTeamDigest.jsonString(run)
        if let event = conversation.events.first(where: { $0.id == eventID }) {
            event.content = content
        } else {
            modelContext.insert(ConversationEventRecord(
                id: eventID, conversationId: conversation.id, type: ConversationEventRecord.collectiveReviewRunType,
                content: content, timestamp: run.createdAt, conversation: conversation
            ))
        }
    }

    func publish(_ run: ReviewTeamRun) {
        activity.setCollectiveWorking(run.phase.isWorking || run.phase == .awaitingDecision,
                                      identifier: run.identifier, conversationID: run.conversationID)
        NotificationCenter.default.post(name: .pullRequestReviewRunsChanged, object: nil)
    }

    /// Startup discovery can still be running when the user launches a review; disk is authoritative until recovery catches up.
    func hasUnfinishedReview(for identifier: PullRequestIdentifier, excludingConversationID: String? = nil) throws -> Bool {
        let descriptor = FetchDescriptor<Conversation>(predicate: #Predicate { $0.pullRequestReviewRunJSON != nil })
        return try modelContext.fetch(descriptor).contains { conversation in
            guard conversation.id != excludingConversationID else { return false }
            guard conversation.thread?.archivedAt == nil, let run = try conversation.collectiveReviewRun() else { return false }
            guard run.identifier == identifier, run.phase.isUnfinished else { return false }
            return try !cancellationStore.contains(runID: run.id)
        }
    }

    /// The retry guard proves all workers settled; cancelling their run ID would permanently deny new executions.
    func replaceSettledTask(with run: ReviewTeamRun) {
        tasks.removeValue(forKey: run.conversationID)?.cancel()
        schedule(run)
    }

    func recordRetryFailure(_ error: Error, conversationID: String) {
        runs[conversationID]?.error = ReviewTeamDiagnostics.persisted(error)
        if let run = runs[conversationID] { publish(run) }
    }

    /// Returns true when a saved cancellation or unreadable receipt prevents automatic recovery.
    private func restoreCancellationIfNeeded(_ savedRun: ReviewTeamRun) -> Bool {
        guard savedRun.phase.isUnfinished else { return false }
        do {
            guard try cancellationStore.contains(runID: savedRun.id) else { return false }
            cancel(conversationID: savedRun.conversationID)
        } catch {
            var run = savedRun
            run.phase = .failed
            run.requiresNewRun = true
            run.error = "Could not verify saved cancellation. Start a new review."
            run.finishRunningAttempts(as: .interrupted, error: run.error)
            do { try persist(run) } catch {
                runs[run.conversationID] = run
                publish(run)
            }
        }
        return true
    }

    private func schedule(_ run: ReviewTeamRun) {
        tasks[run.conversationID] = Task { [weak self] in
            guard let self else { return }
            do {
                try await perform(conversationID: run.conversationID, generation: run.generation)
            } catch {
                if var current = try? requireActive(run.conversationID, generation: run.generation) {
                    current.phase = .failed
                    current.error = ReviewTeamDiagnostics.persisted(error)
                    current.finishRunningAttempts(as: .failed, error: current.error)
                    current.requiresNewRun = (error as? ReviewTeamError).map {
                        $0 == .revisionChanged || $0 == .conflict || $0 == .retryInputChanged
                    } ?? false
                    if case .attemptLimit? = error as? ReviewTeamHistoryCaptureError { current.requiresNewRun = true }
                    try? persist(current)
                }
            }
            if runs[run.conversationID]?.generation == run.generation {
                tasks.removeValue(forKey: run.conversationID)
                // A decision can immediately resume this run ID; leave its packets for terminal cleanup.
                if runs[run.conversationID]?.phase == .awaitingDecision { return }
                try? await packets.remove(runID: run.id)
            }
        }
    }

    private func observeActions() {
        for name in [Notification.Name.reviewTeamCancelRequested, .reviewTeamRetryRequested, .reviewTeamRetryFailedRequested,
                     .reviewTeamContinueRequested,
                     .reviewTeamConversationWillClose, .reviewTeamConversationDidDelete] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let conversationID = note.userInfo?["conversationID"] as? String else { return }
                let runID = note.userInfo?["runID"] as? String
                let generation = note.userInfo?["generation"] as? Int
                MainActor.assumeIsolated {
                    if name == .reviewTeamConversationDidDelete {
                        self?.conversationDidDelete(conversationID)
                    } else if name == .reviewTeamRetryRequested {
                        self?.retry(conversationID: conversationID)
                    } else if name == .reviewTeamRetryFailedRequested {
                        guard let runID, let generation else { return }
                        self?.retryFailedReviewers(conversationID: conversationID, runID: runID, generation: generation)
                    } else if name == .reviewTeamContinueRequested {
                        guard let runID, let generation else { return }
                        self?.continueWithMajority(conversationID: conversationID, runID: runID, generation: generation)
                    } else if name == .reviewTeamCancelRequested {
                        self?.cancel(conversationID: conversationID, runID: runID, generation: generation)
                    } else {
                        self?.cancel(conversationID: conversationID)
                    }
                }
            })
        }
    }
}
