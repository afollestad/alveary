import Foundation
import SwiftData

@MainActor
extension ScheduledTaskSchedulerCoordinator {
    func persist(
        _ result: ScheduledTaskRunExecutionResult,
        for runID: PersistentIdentifier
    ) async {
        await persistTerminalResult(result, runID: runID, finishedAt: now())
    }

    func persistFailedRunIfNeeded(
        for launch: ScheduledTaskActiveLaunch,
        error: Error
    ) async {
        guard let runID = launch.runID else {
            return
        }
        await persistTerminalResult(
            .failed(message: error.localizedDescription),
            runID: runID,
            finishedAt: now()
        )
    }

    func persistInterruptedRunIfNeeded(for launch: ScheduledTaskActiveLaunch) async {
        guard let runID = launch.runID,
              let run = modelContext.resolveScheduledTaskRun(id: runID) else {
            return
        }
        guard !run.hasKnownTerminalStatus || launch.stopRequested else {
            return
        }
        if launch.shutdownRequested, run.status == .claimed {
            return
        }
        await persistTerminalResult(.interrupted, runID: runID, finishedAt: now())
    }

    func persistTerminalResult(
        _ result: ScheduledTaskRunExecutionResult,
        runID: PersistentIdentifier,
        finishedAt: Date,
        forceSaveTerminal: Bool = false
    ) async {
        await flushPendingChangesBeforeTerminalMutation()
        guard let initialRun = modelContext.resolveScheduledTaskRun(id: runID) else {
            return
        }
        if !forceSaveTerminal, initialRun.hasKnownTerminalStatus {
            reconcileTerminalConversations(for: initialRun)
            return
        }
        while let run = modelContext.resolveScheduledTaskRun(id: runID) {
            applyTerminalResult(result, finishedAt: finishedAt, to: run)
            let conversation = run.thread?.conversations.first(where: \.isMain)
            let conversationIDs = run.thread?.conversations.map(\.id) ?? []
            conversation?.isUnread = true
            do {
                try saveTerminalState()
                publishTerminalState(
                    result,
                    conversationID: conversation?.id,
                    conversationIDsToReconcile: conversationIDs
                )
                return
            } catch {
                await persistenceRetryWait()
            }
        }
    }

    func preserveClaimedRun(
        runID: PersistentIdentifier,
        error: Error
    ) async {
        await flushPendingChangesBeforeTerminalMutation()
        while let run = modelContext.resolveScheduledTaskRun(id: runID) {
            if run.thread != nil {
                await persistTerminalResult(
                    .failed(message: error.localizedDescription),
                    runID: runID,
                    finishedAt: now(),
                    forceSaveTerminal: true
                )
                return
            }
            guard let status = run.decodedStatus,
                  !status.isTerminal else {
                return
            }
            run.status = .claimed
            run.preparationStartedAt = nil
            run.preparedWorkspaceRoot = nil
            run.preparedWorkspaceOwnershipStrategy = nil
            run.preparedWorkspaceMarkerID = nil
            run.finishedAt = nil
            run.lastError = error.localizedDescription
            do {
                try saveTerminalState()
                return
            } catch {
                await persistenceRetryWait()
            }
        }
    }

    func flushPendingChangesBeforeTerminalMutation() async {
        while modelContext.hasChanges {
            do {
                try modelContext.save()
                return
            } catch {
                await persistenceRetryWait()
            }
        }
    }

    func applyTerminalResult(
        _ result: ScheduledTaskRunExecutionResult,
        finishedAt: Date,
        to run: ScheduledTaskRun
    ) {
        switch result {
        case .succeeded:
            run.status = .success
            run.lastError = nil
        case .failed(let message):
            run.status = .failure
            run.lastError = message
        case .interrupted:
            run.status = .interrupted
            run.lastError = nil
        }
        run.finishedAt = finishedAt
        run.requiresFinalizationRecovery = false
        run.thread?.modifiedAt = finishedAt
    }

    func publishTerminalState(
        _ result: ScheduledTaskRunExecutionResult,
        conversationID: String?,
        conversationIDsToReconcile: [String]
    ) {
        if let conversationID {
            notificationManager.refreshBadgeCount()
            NotificationCenter.default.post(
                name: .agentStatusChanged,
                object: nil,
                userInfo: ["conversationId": conversationID]
            )
            if case let .failed(message) = result, let message {
                notificationManager.handleEvent(.error(message: message), conversationId: conversationID)
            }
        }

        for conversationID in conversationIDsToReconcile {
            terminalConversationReconciliation(conversationID)
        }
    }

    func reconcileTerminalConversations(for run: ScheduledTaskRun) {
        for conversationID in run.thread?.conversations.map(\.id) ?? [] {
            terminalConversationReconciliation(conversationID)
        }
    }
}
