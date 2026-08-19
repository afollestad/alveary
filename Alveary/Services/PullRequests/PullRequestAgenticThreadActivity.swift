import Foundation

/// Which of a pull request's agentic footer routes are working right now, so the detail pane can
/// show the running one as a spinner and refuse a second click on that same route.
///
/// App-scoped rather than per-window or per-pane: the pane is origin-scoped, so it unmounts the
/// moment the user looks at anything else and its session is discarded on dismissal. A run tracked
/// there would be forgotten by walking away from it. `PullRequestsViewModel` mirrors what the
/// footer needs onto the pane session — nothing reads this from a `body`.
///
/// ## The phase machine
///
/// An entry is `.pending` from the click until its conversation is first seen working, then
/// `.running` until that turn ends:
///
/// - `begin` on the click, before a thread exists.
/// - `attach` once `start` has answered with a conversation id.
/// - `armStartupGrace` once the first prompt has been dispatched. Before that there is nothing to
///   wait on; after it, a turn that never starts — `setupAndStart` threw — would strand the entry
///   at `.pending`, so the grace drops it.
/// - Promotion to `.running` on the first working signal, which cancels the grace.
/// - Removal on the first non-working signal *after* promotion.
///
/// ## Why those signals
///
/// Working is `.busy` **or** `.waitingForUser`, so a turn paused on a tool approval still counts —
/// the run is not over, it needs the user inside it. Ending on `.idle` / `.neutral` / `.stopped` /
/// `.error` is what scopes the indicator to the spawned thread's *first turn*: a later turn the
/// user starts by hand does not light the pull request's button back up. A deleted thread clears
/// its status to `.neutral`, so it ends on the same rule with nothing extra to observe.
///
/// Promotion has to latch. `.idle` is also what the runtime reports at buffer install when a spawn
/// carries no immediate turn, so an entry that ended on the first non-working signal it saw would
/// end before its turn began.
///
/// ## Why the live signal is re-read
///
/// `start` creates its dispatch task before it returns, so a fast turn can report `.busy` before
/// the caller has had a chance to `attach` — and a notification that arrives while no entry names
/// that conversation is dropped on the floor. Re-reading `currentSignal` at attach and at grace
/// expiry recovers that case; the notification alone would leave such a run stuck at `.pending`
/// until the grace killed a spinner that should have been running.
@MainActor
final class PullRequestAgenticThreadActivity {
    struct Key: Hashable {
        let identifier: PullRequestIdentifier
        let kind: PullRequestAgenticThreadService.Kind
    }

    private enum Phase {
        case pending
        case running
    }

    private struct Entry {
        var phase = Phase.pending
        var conversationID: String?
        var graceTask: Task<Void, Never>?
    }

    private static let workingSignals: Set<ActivitySignal> = [.busy, .waitingForUser]

    private let notificationCenter: NotificationCenter
    /// How long a dispatched prompt has to produce a turn before its entry is dropped. Long by
    /// default because it spans a provider process launch; an init parameter so tests need not sleep.
    private let startupGrace: Duration
    /// The runtime's current signal for a conversation. A closure rather than `AgentsManager` so a
    /// test can drive it without a runtime, matching how this scope injects `directoryExists`.
    private let currentSignal: @MainActor (String) -> ActivitySignal
    private var entries: [Key: Entry] = [:]
    private var statusObserver: (any NSObjectProtocol)?

    init(
        notificationCenter: NotificationCenter = .default,
        startupGrace: Duration = .seconds(30),
        currentSignal: @escaping @MainActor (String) -> ActivitySignal = { _ in .neutral }
    ) {
        self.notificationCenter = notificationCenter
        self.startupGrace = startupGrace
        self.currentSignal = currentSignal
        observeAgentStatus()
    }

    deinit {
        MainActor.assumeIsolated {
            if let statusObserver {
                notificationCenter.removeObserver(statusObserver)
            }
            for entry in entries.values {
                entry.graceTask?.cancel()
            }
        }
    }

    // MARK: - Reads

    func isWorking(_ identifier: PullRequestIdentifier, kind: PullRequestAgenticThreadService.Kind) -> Bool {
        entries[Key(identifier: identifier, kind: kind)] != nil
    }

    func workingKinds(for identifier: PullRequestIdentifier) -> Set<PullRequestAgenticThreadService.Kind> {
        Set(entries.keys.lazy.filter { $0.identifier == identifier }.map(\.kind))
    }

    // MARK: - Lifecycle

    /// Marks the route busy on the click's own turn, so the spinner is up before the spawn's first
    /// suspension and a second click on the same route is refused by the caller's guard.
    func begin(_ identifier: PullRequestIdentifier, kind: PullRequestAgenticThreadService.Kind) {
        let key = Key(identifier: identifier, kind: kind)
        guard entries[key] == nil else {
            return
        }
        entries[key] = Entry()
        announce()
    }

    /// Names the conversation whose signals this entry follows. Promotes immediately when that
    /// conversation is already working — see the type's note on re-reading the live signal.
    func attach(
        conversationID: String,
        identifier: PullRequestIdentifier,
        kind: PullRequestAgenticThreadService.Kind
    ) {
        let key = Key(identifier: identifier, kind: kind)
        guard entries[key] != nil else {
            return
        }
        entries[key]?.conversationID = conversationID
        promoteIfWorking(key)
    }

    /// Starts the bounded wait for the turn to appear. A no-op once the entry is already running.
    func armStartupGrace(_ identifier: PullRequestIdentifier, kind: PullRequestAgenticThreadService.Kind) {
        let key = Key(identifier: identifier, kind: kind)
        guard let entry = entries[key], entry.phase == .pending else {
            return
        }
        guard !promoteIfWorking(key) else {
            return
        }
        entry.graceTask?.cancel()
        entries[key]?.graceTask = Task { [weak self, startupGrace] in
            try? await Task.sleep(for: startupGrace)
            guard !Task.isCancelled else {
                return
            }
            self?.expireStartupGrace(key)
        }
    }

    /// Ends the route: a spawn that threw, or a dispatch that never reached the prompt.
    func end(_ identifier: PullRequestIdentifier, kind: PullRequestAgenticThreadService.Kind) {
        remove(Key(identifier: identifier, kind: kind))
    }

    // MARK: - Runtime signals

    /// Observed synchronously (`queue: nil`) so a transition reaches the mirrored pane session on
    /// the poster's own turn. Every poster is `@MainActor`, which is what `assumeIsolated` rests on.
    private func observeAgentStatus() {
        statusObserver = notificationCenter.addObserver(
            forName: .agentStatusChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Unpacked out here, not inside the hop: `Notification` is not `Sendable`, while the
            // two values are. A post carrying no `signal` is an unread-flag flip from
            // `DefaultNotificationManager` sharing this bus rather than a runtime transition —
            // reading one as a transition would end entries on unread changes.
            guard let conversationID = notification.userInfo?[
                AgentStatusChangedKey.conversationID
            ] as? String,
                let signal = notification.userInfo?[AgentStatusChangedKey.signal] as? ActivitySignal else {
                return
            }
            MainActor.assumeIsolated {
                self?.handleAgentStatusChange(conversationID: conversationID, signal: signal)
            }
        }
    }

    private func handleAgentStatusChange(conversationID: String, signal: ActivitySignal) {
        guard let key = entries.first(where: { $0.value.conversationID == conversationID })?.key else {
            return
        }
        if Self.workingSignals.contains(signal) {
            promote(key)
        } else if entries[key]?.phase == .running {
            remove(key)
        }
    }

    @discardableResult
    private func promoteIfWorking(_ key: Key) -> Bool {
        guard let conversationID = entries[key]?.conversationID,
              Self.workingSignals.contains(currentSignal(conversationID)) else {
            return false
        }
        promote(key)
        return true
    }

    private func promote(_ key: Key) {
        guard let entry = entries[key], entry.phase == .pending else {
            return
        }
        entry.graceTask?.cancel()
        entries[key]?.graceTask = nil
        entries[key]?.phase = .running
    }

    /// The turn may simply have been slow to start, so the live signal gets the last word before
    /// the entry is dropped.
    private func expireStartupGrace(_ key: Key) {
        guard let entry = entries[key], entry.phase == .pending else {
            return
        }
        guard !promoteIfWorking(key) else {
            return
        }
        remove(key)
    }

    private func remove(_ key: Key) {
        guard let entry = entries.removeValue(forKey: key) else {
            return
        }
        entry.graceTask?.cancel()
        announce()
    }

    private func announce() {
        notificationCenter.post(name: .pullRequestAgenticThreadActivityChanged, object: nil)
    }
}

extension Notification.Name {
    /// Posted whenever a pull request's set of working agentic routes changes. Declared beside the
    /// tracker that posts it, as `.agentStatusChanged` is declared beside `AgentsManager`.
    static let pullRequestAgenticThreadActivityChanged = Notification.Name(
        "pullRequestAgenticThreadActivityChanged"
    )
}
