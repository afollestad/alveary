import Foundation
import Observation

/// The pull requests the user ignored: hidden from the Pull requests screen and unsubscribed
/// from their GitHub notifications. App-scoped and `@Observable`, so every window hides the
/// same rows.
///
/// The list is local because GitHub cannot enumerate it — no search qualifier or endpoint lists
/// unsubscribed threads — and `viewerSubscription` alone cannot stand in for it, since involved
/// pull requests read `UNSUBSCRIBED` without anyone ignoring them. `reconcileIfNeeded` keeps the
/// two in step instead:
///
/// - **Merged or closed** drops the entry; ignoring exists to quiet open work.
/// - **Subscribed again** drops it too — the user resubscribed on github.com, or GitHub did
///   (its docs say an unsubscribe holds until the viewer comments or is mentioned), and either
///   is a reason to see it again. An entry ignored after the sync started, or within
///   `resubscribeGrace` of it, is left alone, so a read that raced the unsubscribe cannot undo it.
/// - **Not returned** (deleted, access lost, SAML) keeps the entry until `lastSeenAt` is older
///   than `unseenRetention`, so a transient null never un-ignores anything while the list
///   still cannot grow forever.
@MainActor @Observable
final class PullRequestIgnoreService {
    /// What the list hides: persisted entries, plus ignores in flight, minus un-ignores in flight.
    private(set) var effectiveIgnoredIDs: Set<PullRequestIdentifier> = []
    /// Pull requests with a subscription change in flight; their controls disable meanwhile.
    private(set) var pendingIDs: Set<PullRequestIdentifier> = []

    static let reconcileInterval: TimeInterval = 5 * 60
    static let unseenRetention: TimeInterval = 30 * 24 * 60 * 60
    static let resubscribeGrace: TimeInterval = 60

    @ObservationIgnored private var entries: [PullRequestIdentifier: IgnoredPullRequestEntry] = [:]
    /// `true` is an ignore in flight, `false` an un-ignore.
    @ObservationIgnored private var pendingIntents: [PullRequestIdentifier: Bool] = [:]
    @ObservationIgnored private var lastReconciledAt: Date?
    @ObservationIgnored private var isLoaded = false
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var reconcileTask: Task<[PullRequestSummary], Never>?
    /// Saves chain onto the previous one so a later snapshot can never land before an earlier.
    @ObservationIgnored private var persistTask: Task<Void, Never>?

    private let service: any PullRequestsService
    private let store: IgnoredPullRequestsStore?
    private let now: @MainActor () -> Date

    init(
        service: any PullRequestsService,
        store: IgnoredPullRequestsStore?,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.service = service
        self.store = store
        self.now = now
    }

    func isIgnored(_ id: PullRequestIdentifier) -> Bool {
        effectiveIgnoredIDs.contains(id)
    }

    /// Reads the file once; every caller awaits the same load, so nothing writes over entries
    /// that have not arrived yet.
    ///
    /// Returns without suspending once loaded (and at once with no store): the list screen awaits
    /// this ahead of its own loads, and a needless hop there let a tab switch's load overtake it.
    func loadIfNeeded() async {
        guard !isLoaded else {
            return
        }
        guard let store else {
            isLoaded = true
            return
        }
        if loadTask == nil {
            loadTask = Task {
                let snapshot = await store.load()
                self.entries = Dictionary(snapshot.entries.map { ($0.id, $0) }, uniquingKeysWith: { _, latest in latest })
                self.lastReconciledAt = snapshot.lastReconciledAt
                self.isLoaded = true
                self.publish()
            }
        }
        await loadTask?.value
    }

    /// Unsubscribes (`ignored`) or resubscribes on GitHub, and records the change only once
    /// GitHub accepts it. The row reads as changed while the request runs and reverts if it
    /// throws. A second call for a pull request already in flight is dropped.
    ///
    /// An ignore that reads back `SUBSCRIBED` throws: persisting it would only have the next sync
    /// auto-unignore it.
    func setIgnored(_ ignored: Bool, for id: PullRequestIdentifier) async throws {
        await loadIfNeeded()
        guard pendingIntents[id] == nil, (entries[id] != nil) != ignored else {
            return
        }
        pendingIntents[id] = ignored
        publish()
        defer {
            pendingIntents[id] = nil
            publish()
        }
        try await GitHubRequestOrigin.$current.withValue("pr-ignore") {
            guard let snapshot = try await service.fetchSubscriptionStates(for: [id])[id] else {
                throw PullRequestsServiceError.transport("GitHub did not return \(id.displayKey).")
            }
            let state = try await service.updatePullRequestSubscription(nodeID: snapshot.nodeID, subscribed: !ignored)
            if ignored, state == .subscribed {
                throw PullRequestsServiceError.transport("GitHub kept you subscribed to \(id.displayKey).")
            }
        }
        if ignored {
            let date = now()
            entries[id] = IgnoredPullRequestEntry(id: id, ignoredAt: date, lastSeenAt: date)
        } else {
            entries[id] = nil
        }
        persist()
    }

    /// Syncs every entry against GitHub and returns the fresh row of each pull request it read,
    /// for the caller to write into its cached list. At most once per `reconcileInterval` unless
    /// `force`d, never with nothing ignored, and a caller arriving mid-sync joins it.
    ///
    /// A failed read changes nothing and is not stamped, so the next refresh tries again.
    func reconcileIfNeeded(force: Bool) async -> [PullRequestSummary] {
        await loadIfNeeded()
        if let reconcileTask {
            return await reconcileTask.value
        }
        guard !entries.isEmpty else {
            return []
        }
        if !force, let lastReconciledAt, now().timeIntervalSince(lastReconciledAt) < Self.reconcileInterval {
            return []
        }
        let task = Task { await self.reconcile() }
        reconcileTask = task
        let summaries = await task.value
        reconcileTask = nil
        return summaries
    }

    private func reconcile() async -> [PullRequestSummary] {
        let startedAt = now()
        let ids = entries.keys.sorted { $0.displayKey < $1.displayKey }
        let snapshots: [PullRequestIdentifier: PullRequestSubscriptionSnapshot]
        do {
            snapshots = try await GitHubRequestOrigin.$current.withValue("pr-ignore") {
                try await service.fetchSubscriptionStates(for: ids)
            }
        } catch {
            return []
        }
        let date = now()
        lastReconciledAt = date
        for id in ids {
            guard var entry = entries[id], pendingIntents[id] == nil else {
                continue
            }
            guard let snapshot = snapshots[id] else {
                if date.timeIntervalSince(entry.lastSeenAt) > Self.unseenRetention {
                    entries[id] = nil
                }
                continue
            }
            switch snapshot.summary.status {
            case .merged, .closed:
                entries[id] = nil
                continue
            case .open, .draft:
                break
            }
            if snapshot.subscription == .subscribed,
               entry.ignoredAt < startedAt.addingTimeInterval(-Self.resubscribeGrace) {
                entries[id] = nil
                continue
            }
            entry.lastSeenAt = date
            entries[id] = entry
        }
        publish()
        persist()
        return ids.compactMap { snapshots[$0]?.summary }
    }

    private func publish() {
        var ids = Set(entries.keys)
        for (id, ignoring) in pendingIntents {
            if ignoring {
                ids.insert(id)
            } else {
                ids.remove(id)
            }
        }
        if ids != effectiveIgnoredIDs {
            effectiveIgnoredIDs = ids
        }
        let pending = Set(pendingIntents.keys)
        if pending != pendingIDs {
            pendingIDs = pending
        }
    }

    private func persist() {
        guard let store else {
            return
        }
        let snapshot = IgnoredPullRequestsSnapshot(
            entries: entries.values.sorted { $0.id.displayKey < $1.id.displayKey },
            lastReconciledAt: lastReconciledAt
        )
        let previous = persistTask
        persistTask = Task {
            await previous?.value
            await store.save(snapshot)
        }
    }

    #if DEBUG
    /// Lets tests wait for the file write a change scheduled.
    func waitForPendingSave() async {
        await persistTask?.value
    }
    #endif
}
