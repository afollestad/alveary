import Foundation
import Observation
import SwiftData

/// Conversations holding a permission prompt, `AskUserQuestion`, or `ExitPlanMode` the user never
/// answered, read from persistence rather than from the runtime.
///
/// `DefaultAgentsManager.statusSnapshot` already reports these while the app runs, but it is
/// in-memory, so a relaunch loses every waiting dot. It deliberately stays that way: that snapshot
/// also drives the keep-awake assertion and the sudden-termination gate, and seeding it from
/// history would hold a power assertion open for a prompt nobody is waiting on. This registry is
/// the durable half, unioned in at display time through `ConversationDecisionAttention`.
///
/// Distinct from `SidebarViewModel.hasUnresolvedApproval`, which gates forking and Task moves and
/// counts the transient `.pending`/`.approving` statuses as unresolved. Those are live states the
/// runtime already reports as waiting; here only a never-answered row counts. Do not merge them.
@MainActor
@Observable
final class UnresolvedApprovalRegistry {
    @ObservationIgnored private let modelContext: ModelContext
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var observationTask: Task<Void, Never>?
    @ObservationIgnored private var hasLoaded = false

    private(set) var conversationIDs: Set<String> = []

    init(
        modelContext: ModelContext,
        notificationCenter: NotificationCenter = .default
    ) {
        self.modelContext = modelContext
        self.notificationCenter = notificationCenter
        observeChanges()
    }

    deinit {
        observationTask?.cancel()
    }

    /// Runs the first load off the launch path. The sibling proposal coordinators fetch in `init`,
    /// but they read small tables; this one scans `ConversationEventRecord`, the largest in the
    /// store, and `init` runs during `ContentView` construction. A dot arriving a frame late is
    /// invisible; a blocked launch is not.
    func start() {
        guard !hasLoaded else {
            return
        }
        hasLoaded = true
        reload()
    }

    /// One fetch for the candidates, then at most two more per candidate probed.
    ///
    /// Probing stops at a conversation's first still-open row, because one is all the dot needs.
    /// That matters: a long-lived store accumulates never-stamped rows from turns that ended
    /// without a host-side decision, and probing every one of them would put a fetch pair each on
    /// the main actor. The overwhelmingly common case is no candidates at all, which costs the
    /// single fetch and no probes.
    func reload() {
        let recordType = ConversationEventRecord.toolApprovalType
        let descriptor = FetchDescriptor<ConversationEventRecord>(
            predicate: #Predicate {
                $0.type == recordType && $0.toolApprovalStatus == nil
            }
        )
        let candidates = (try? modelContext.fetch(descriptor)) ?? []
        var waiting: Set<String> = []
        for record in candidates where !waiting.contains(record.conversationId) {
            guard !isResolved(record) else {
                continue
            }
            waiting.insert(record.conversationId)
        }
        conversationIDs = waiting
    }
}

private extension UnresolvedApprovalRegistry {
    /// A never-answered row is not proof of an open prompt: the provider can run the tool or end
    /// the turn without Alveary stamping the row, and counting those would strand a dot forever.
    func isResolved(_ record: ConversationEventRecord) -> Bool {
        modelContext.hasToolApprovalResolution(
            conversationID: record.conversationId,
            toolUseId: record.toolId ?? record.id,
            approvalTimestamp: record.timestamp
        )
    }

    func observeChanges() {
        let notifications = notificationCenter.notifications(named: .agentStatusChanged)
        observationTask = Task { @MainActor [weak self] in
            for await notification in notifications {
                guard !Task.isCancelled else {
                    return
                }
                self?.handleStatusChange(notification)
            }
        }
    }

    /// `.agentStatusChanged` fires on every busy/idle flip of every streaming turn, and a reload
    /// costs at least one fetch. An approval row can only appear when a conversation starts
    /// waiting, and can only clear for a conversation already counted, so everything else is
    /// skipped. A post carrying no conversation reloads, because it cannot be ruled out.
    ///
    /// This is eventually consistent by design: the waiting post can beat the debounced save that
    /// persists the approval row, leaving that reload blind to it. Every such window is covered by
    /// the runtime itself reporting `.waitingForUser` — the union in `ThreadStatus` shows the dot
    /// either way — and the resolution's own status flip triggers the corrective reload.
    func handleStatusChange(_ notification: Notification) {
        guard hasLoaded else {
            return
        }
        let signal = notification.userInfo?[AgentStatusChangedKey.signal] as? ActivitySignal
        let conversationID = notification.userInfo?[AgentStatusChangedKey.conversationID] as? String
        let mayHaveAppeared = signal == .waitingForUser
        let mayHaveCleared = conversationID.map(conversationIDs.contains) ?? true
        guard mayHaveAppeared || mayHaveCleared else {
            return
        }
        reload()
    }
}
