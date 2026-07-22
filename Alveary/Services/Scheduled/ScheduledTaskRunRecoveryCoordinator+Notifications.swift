import Foundation
import SwiftData

extension ScheduledTaskRunRecoveryCoordinator {
    func reconciliationConversationIDs(for run: ScheduledTaskRun) -> [String] {
        switch run.decodedDestinationSnapshot {
        case .newThread:
            return run.thread?.conversations.map(\.id) ?? []
        case .existingThread:
            return run.targetThread?.conversations.map(\.id) ?? []
        case nil:
            var seenConversationIDs = Set<String>()
            let relationshipConversationIDs = (run.thread?.conversations.map(\.id) ?? []) +
                (run.targetThread?.conversations.map(\.id) ?? [])
            return relationshipConversationIDs.filter { seenConversationIDs.insert($0).inserted }
        }
    }

    func presentationConversation(for run: ScheduledTaskRun) -> Conversation? {
        switch run.decodedDestinationSnapshot {
        case .existingThread:
            guard let targetConversationID = run.targetConversationIDSnapshot,
                  let targetThread = run.targetThread else {
                return nil
            }
            return targetThread.conversations.first {
                $0.isMain &&
                    $0.id == targetConversationID &&
                    $0.thread?.persistentModelID == targetThread.persistentModelID
            }
        case .newThread:
            return run.thread?.conversations.first(where: \.isMain)
        case nil:
            return nil
        }
    }

    func makeInterruptedOccurrenceNote(
        for run: ScheduledTaskRun,
        conversation: Conversation,
        at actionDate: Date
    ) -> ConversationEventRecord {
        let timeZone = TimeZone(identifier: run.timeZoneIdentifierSnapshot) ?? TimeZone(secondsFromGMT: 0) ?? .current
        return ConversationEventRecord(
            id: "scheduled-task-\(run.id)",
            conversationId: conversation.id,
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: noteFormatter.text(title: run.titleSnapshot, occurrenceAt: run.occurrenceAt, timeZone: timeZone),
            timestamp: actionDate,
            conversation: conversation
        )
    }

    func insertInterruptedOccurrenceNoteIfNeeded(
        for run: ScheduledTaskRun,
        at actionDate: Date
    ) {
        guard let conversation = presentationConversation(for: run) else {
            return
        }
        let noteID = "scheduled-task-\(run.id)"
        guard !conversation.events.contains(where: { $0.id == noteID }) else {
            return
        }
        let latestEventTimestamp = conversation.events.map(\.timestamp).max()
        let noteTimestamp = latestEventTimestamp.map {
            max(actionDate, $0.addingTimeInterval(0.001))
        } ?? actionDate
        let note = makeInterruptedOccurrenceNote(
            for: run,
            conversation: conversation,
            at: noteTimestamp
        )
        modelContext.insert(note)
    }

    @discardableResult
    func supersedePendingInteractions(for run: ScheduledTaskRun) -> Bool {
        guard let conversation = presentationConversation(for: run) else {
            return false
        }
        var didChange = false
        for record in scheduledInteractionRecords(for: run, in: conversation) {
            if record.type == "tool_approval", record.toolApprovalStatus == nil {
                record.toolApprovalStatus = ToolApprovalStatus.superseded.rawValue
                didChange = true
            }
            if record.type == "tool_call",
               record.toolName == "AskUserQuestion",
               record.content?.isEmpty != false {
                record.content = ChatItemGrouper.handledPromptSummary
                didChange = true
            }
        }
        return didChange
    }

    func scheduledInteractionRecords(
        for run: ScheduledTaskRun,
        in conversation: Conversation
    ) -> [ConversationEventRecord] {
        let orderedRecords = conversation.events.sorted {
            if $0.timestamp != $1.timestamp {
                return $0.timestamp < $1.timestamp
            }
            return $0.id < $1.id
        }
        switch run.decodedDestinationSnapshot {
        case .newThread:
            return orderedRecords
        case .existingThread:
            // Materialization inserts the note before executor activation. `startedAt` is the
            // durable boundary proving that later interactions belong to the scheduled turn,
            // rather than to manual work that raced with preparation.
            guard run.startedAt != nil else {
                return []
            }
            let noteID = "scheduled-task-\(run.id)"
            guard let noteIndex = orderedRecords.firstIndex(where: { $0.id == noteID }) else {
                return []
            }
            return Array(orderedRecords.dropFirst(noteIndex + 1))
        case nil:
            return []
        }
    }

    func publishRecoveredConversationChanges(
        for runIDs: [PersistentIdentifier],
        refreshBadgeCount: Bool
    ) {
        let runIDSet = Set(runIDs)
        let runs = (try? modelContext.fetch(FetchDescriptor<ScheduledTaskRun>()))?
            .filter { runIDSet.contains($0.persistentModelID) } ?? []
        let conversationIDsToReconcile = runs.flatMap { reconciliationConversationIDs(for: $0) }
        if refreshBadgeCount, !conversationIDsToReconcile.isEmpty {
            notificationManager.refreshBadgeCount()
        }
        for run in runs {
            guard let conversation = presentationConversation(for: run) else {
                continue
            }
            let interactionIDs: Set<String> = Set(
                scheduledInteractionRecords(for: run, in: conversation).compactMap { record in
                    guard record.type == "tool_approval" ||
                        (record.type == "tool_call" && record.toolName == "AskUserQuestion") else {
                        return nil
                    }
                    return record.toolId ?? record.id
                }
            )
            guard !interactionIDs.isEmpty else {
                continue
            }
            controllerRegistry.supersedeScheduledTaskPendingInteractions(
                conversationID: conversation.id,
                interactionIDs: interactionIDs
            )
        }
        for conversationID in Set(conversationIDsToReconcile) {
            controllerRegistry.reconcileScheduledTaskTerminalState(conversationID: conversationID)
            NotificationCenter.default.post(
                name: .agentStatusChanged,
                object: nil,
                userInfo: ["conversationId": conversationID]
            )
        }
    }
}
