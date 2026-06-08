import Foundation

extension ChatItemGrouper {
    func handleCenteredNoteToolCall(_ event: ConversationEventRecord) {
        guard let toolName = event.toolName,
              let noteKind = centeredTranscriptNoteKind(forToolNamed: toolName) else {
            return
        }

        let toolId = event.toolId ?? event.id
        centeredNoteToolKinds[toolId] = noteKind
    }

    func handleCenteredNoteToolResult(
        toolId: String,
        kind: CenteredTranscriptNoteKind,
        event: ConversationEventRecord
    ) {
        if kind == .exitedPlanMode,
           toolApprovalStatusesByToolId[toolId] == .denied {
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.centeredNote(id: "note-\(toolId)", kind: .stayingInPlanMode))
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
                toolName: centeredToolName(for: kind),
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
        appendTranscriptItem(.centeredNote(id: "note-\(toolId)", kind: kind))
    }

    func centeredTranscriptNoteKind(forToolNamed toolName: String) -> CenteredTranscriptNoteKind? {
        switch toolName {
        case "EnterPlanMode":
            return .enteredPlanMode
        case "ExitPlanMode":
            return .exitedPlanMode
        default:
            return nil
        }
    }

    func centeredToolName(for kind: CenteredTranscriptNoteKind) -> String {
        switch kind {
        case .enteredPlanMode:
            return "EnterPlanMode"
        case .exitedPlanMode, .stayingInPlanMode:
            return "ExitPlanMode"
        case .interrupted, .sessionHandoff, .contextCompactionStarted, .contextCompactionCompleted, .contextCompactionFailed:
            return "Tool"
        }
    }

    func handleContextCompaction(_ event: ConversationEventRecord) {
        currentToolApprovalBatch = nil
        flushGroup()
        flushSubAgents()
        replaceOrAppendTranscriptItem(
            .centeredNote(
                id: contextCompactionNoteId(for: event),
                kind: contextCompactionNoteKind(for: event)
            )
        )
    }

    private func contextCompactionNoteId(for event: ConversationEventRecord) -> String {
        "context-compaction-\(event.toolId ?? event.id)"
    }

    private func contextCompactionNoteKind(for event: ConversationEventRecord) -> CenteredTranscriptNoteKind {
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
        case "stop" where ConversationInterruption.isDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            markIncompleteToolsInterrupted()
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.centeredNote(id: event.id, kind: .interrupted))
        case "stop" where ConversationSessionHandoff.isDisplayMessage(event.content):
            currentToolApprovalBatch = nil
            flushGroup()
            flushSubAgents()
            appendTranscriptItem(.centeredNote(id: event.id, kind: .sessionHandoff))
        default:
            break
        }
    }
}
