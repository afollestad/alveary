import Foundation

/// App-scoped activity shared by UI and host-tool launches, independent of the pane's lifetime.
///
/// The launcher marks preparation pending before preflight, attaches the created task, and arms a
/// startup grace after dispatch. The first busy or waiting-for-user signal latches the route running;
/// only a subsequent idle, neutral, stopped, or error signal ends it. An initial idle signal cannot
/// end a task whose harness has not started yet. Grace expiry clears a dispatched turn that never starts.
///
/// Attach and grace expiry re-read the live signal because a notification may arrive before the
/// conversation is attached. Collective work instead ends when its coordinator releases the route;
/// unrelated harness-turn completion cannot end a team review.
@MainActor
final class PullRequestAgenticThreadActivity {
    struct Key: Hashable {
        let identifier: PullRequestIdentifier
        let kind: PullRequestAgenticThreadService.Kind

        /// GitHub repository casing does not distinguish launch routes.
        init(identifier: PullRequestIdentifier, kind: PullRequestAgenticThreadService.Kind) {
            self.identifier = PullRequestIdentifier(
                owner: identifier.owner.lowercased(), repo: identifier.repo.lowercased(), number: identifier.number
            )
            self.kind = kind
        }
    }

    private enum Phase {
        case pending
        case running
    }

    private struct Entry {
        var phase = Phase.pending
        var conversationID: String?
        var graceTask: Task<Void, Never>?
        var isCollective = false
    }

    private static let workingSignals: Set<ActivitySignal> = [.busy, .waitingForUser]

    private let notificationCenter: NotificationCenter
    /// How long a dispatched prompt has to produce a turn before its entry is dropped. Long by
    /// default because it spans a harness process launch; an init parameter so tests need not sleep.
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
        let normalized = Key(identifier: identifier, kind: .review).identifier
        return Set(entries.keys.lazy.filter { $0.identifier == normalized }.map(\.kind))
    }

    // MARK: - Lifecycle

    /// Marks preparation busy before the launcher's first suspension.
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
        guard let entry = entries[key], entry.phase == .pending, !entry.isCollective else {
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
    func end(_ identifier: PullRequestIdentifier, kind: PullRequestAgenticThreadService.Kind, conversationID: String? = nil) {
        let key = Key(identifier: identifier, kind: kind)
        guard conversationID == nil || entries[key]?.conversationID == conversationID else { return }
        remove(key)
    }

    /// A failed preparation must not clear a run recovered while its validation was suspended.
    func endPending(_ identifier: PullRequestIdentifier, kind: PullRequestAgenticThreadService.Kind) {
        let key = Key(identifier: identifier, kind: kind)
        guard entries[key]?.conversationID == nil else { return }
        remove(key)
    }

    /// Collective work ends at the app-owned staging boundary, never at an unrelated harness turn.
    func setCollectiveWorking(_ working: Bool, identifier: PullRequestIdentifier, conversationID: String) {
        let key = Key(identifier: identifier, kind: .review)
        guard working else {
            if entries[key]?.conversationID == conversationID { remove(key) }
            return
        }
        entries[key]?.graceTask?.cancel()
        entries[key] = Entry(phase: .running, conversationID: conversationID, isCollective: true)
        announce()
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
        guard entries[key]?.isCollective != true else { return }
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
