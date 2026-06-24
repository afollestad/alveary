import Foundation

extension ChatItemGrouper {
    func handleTranscriptNoteToolCall(_ event: ConversationEventRecord) {
        guard let toolName = event.toolName,
              let noteKind = transcriptNoteKind(forToolNamed: toolName) else {
            return
        }

        let toolId = event.toolId ?? event.id
        transcriptNoteToolKinds[toolId] = noteKind
        if let resultEvent = pendingToolResultEventsByToolId.removeValue(forKey: toolId) {
            transcriptNoteToolKinds.removeValue(forKey: toolId)
            handleTranscriptNoteToolResult(toolId: toolId, kind: noteKind, event: resultEvent)
        }
    }

    func handleTranscriptNoteToolResult(
        toolId: String,
        kind: TranscriptNoteKind,
        event: ConversationEventRecord
    ) {
        if kind == .exitedPlanMode,
           toolApprovalStatusesByToolId[toolId] == .denied {
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.transcriptNote(id: "note-\(toolId)", kind: .stayingInPlanMode))
            return
        }

        if event.isError {
            flushGroup()
            flushSubAgents()
            let pendingTool = makePendingToolEntry(id: toolId, event: ConversationEventRecord(
                id: toolId,
                conversationId: event.conversationId,
                type: "tool_call",
                toolId: toolId,
                toolName: transcriptNoteToolName(for: kind),
                toolInput: "{}"
            ))
            appendTranscriptItem(
                .standaloneTool(
                    id: "tool-\(toolId)",
                    tool: completedToolEntry(from: pendingTool, event: event)
                )
            )
            return
        }

        flushGroup()
        flushSubAgents()
        appendTranscriptItem(.transcriptNote(id: "note-\(toolId)", kind: kind))
    }

    func transcriptNoteKind(forToolNamed toolName: String) -> TranscriptNoteKind? {
        switch toolName {
        case "EnterPlanMode":
            return .enteredPlanMode
        case "ExitPlanMode":
            return .exitedPlanMode
        default:
            return nil
        }
    }

    func transcriptNoteToolName(for kind: TranscriptNoteKind) -> String {
        switch kind {
        case .enteredPlanMode:
            return "EnterPlanMode"
        case .exitedPlanMode, .stayingInPlanMode:
            return "ExitPlanMode"
        case .interrupted, .sessionHandoffInProgress, .sessionHandoff, .sessionForked, .steeredConversation,
             .contextCompactionStarted, .contextCompactionCompleted, .contextCompactionFailed:
            return "Tool"
        }
    }

    func handleContextCompaction(_ event: ConversationEventRecord) {
        currentToolApprovalBatch = nil
        flushGroup()
        flushSubAgents()
        replaceOrAppendTranscriptItem(
            .transcriptNote(
                id: contextCompactionNoteId(for: event),
                kind: contextCompactionNoteKind(for: event)
            )
        )
    }

    private func contextCompactionNoteId(for event: ConversationEventRecord) -> String {
        "context-compaction-\(event.toolId ?? event.id)"
    }

    private func contextCompactionNoteKind(for event: ConversationEventRecord) -> TranscriptNoteKind {
        switch event.type {
        case ConversationContextCompaction.completedType:
            return .contextCompactionCompleted
        case ConversationContextCompaction.failedType:
            return .contextCompactionFailed
        default:
            return .contextCompactionStarted
        }
    }

    func handleLifecycleNote(_ event: ConversationEventRecord) {
        switch event.type {
        case ConversationContextCompaction.startedType,
             ConversationContextCompaction.completedType,
             ConversationContextCompaction.failedType:
            handleContextCompaction(event)
        case ConversationEventRecord.steeredConversationType:
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.transcriptNote(id: event.id, kind: .steeredConversation))
        case "stop" where ConversationInterruption.isDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            markIncompleteTranscriptActivityInterrupted()
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.transcriptNote(id: event.id, kind: .interrupted))
        case "stop" where ConversationSessionHandoff.isStartedDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            replaceOrAppendTranscriptItem(.transcriptNote(id: event.id, kind: .sessionHandoffInProgress))
        case "stop" where ConversationSessionHandoff.isCompletedDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            replaceOrAppendTranscriptItem(.transcriptNote(id: event.id, kind: .sessionHandoff))
        case "stop" where ConversationSessionFork.isDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.transcriptNote(id: event.id, kind: .sessionForked))
        default:
            break
        }
    }
}
