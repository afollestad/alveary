import Foundation

enum ChatItem: Identifiable, Equatable {
    case userMessage(id: String, text: String)
    case assistantMessage(id: String, text: String)
    case toolGroup(id: String, tools: [ToolEntry])
    case standaloneTool(id: String, tool: ToolEntry)
    case subAgentBlock(id: String, agents: [SubAgentEntry])
    case taskListBlock(id: String, tasks: [TaskEntry])
    case promptBlock(id: String, prompt: PromptEntry)
    case toolApproval(id: String, approval: ToolApprovalRequest, status: ToolApprovalStatus?)
    case toolApprovalBatch(id: String, approvals: [ToolApprovalRequest], status: ToolApprovalStatus?)
    case centeredNote(id: String, kind: CenteredTranscriptNoteKind)
    case error(id: String, message: String)

    var id: String {
        switch self {
        case .userMessage(let id, _), .assistantMessage(let id, _), .toolGroup(let id, _),
             .standaloneTool(let id, _), .subAgentBlock(let id, _), .taskListBlock(let id, _),
             .promptBlock(let id, _), .toolApproval(let id, _, _), .toolApprovalBatch(let id, _, _),
             .centeredNote(let id, _), .error(let id, _):
            id
        }
    }

    var isUserMessage: Bool {
        if case .userMessage = self {
            return true
        }
        return false
    }

    var isAssistantMessage: Bool {
        if case .assistantMessage = self {
            return true
        }
        return false
    }

    var isTurnInterruptedNote: Bool {
        if case .centeredNote(_, .interrupted) = self {
            return true
        }
        return false
    }
}

extension [ChatItem] {
    var hasInterruptedNoteAfterLatestUserMessage: Bool {
        let latestUserIndex = lastIndex(where: \.isUserMessage)
        let searchStart = latestUserIndex.map { index(after: $0) } ?? startIndex
        return self[searchStart...].contains(where: \.isTurnInterruptedNote)
    }
}

struct PromptEntry: Identifiable, Equatable {
    let id: String
    let questions: [PromptQuestion]
    let submittedSummary: String?

    struct PromptQuestion: Equatable {
        let question: String
        let header: String?
        let options: [PromptOption]
        let multiSelect: Bool
        let allowsCustomResponse: Bool

        init(
            question: String,
            header: String?,
            options: [PromptOption],
            multiSelect: Bool,
            allowsCustomResponse: Bool = true
        ) {
            self.question = question
            self.header = header
            self.options = options
            self.multiSelect = multiSelect
            self.allowsCustomResponse = allowsCustomResponse
        }

        var renderedOptions: [PromptOption] {
            if options.contains(where: \.isCustomResponse) {
                return options
            }
            guard allowsCustomResponse else {
                return options
            }
            return options + [.other]
        }
    }

    struct PromptOption: Equatable {
        static let customResponseID = "__other__"

        let id: String
        let label: String
        let description: String
        let isCustomResponse: Bool

        init(
            id: String? = nil,
            label: String,
            description: String,
            isCustomResponse: Bool = false
        ) {
            self.id = id ?? label
            self.label = label
            self.description = description
            self.isCustomResponse = isCustomResponse
        }

        static let other = PromptOption(
            id: customResponseID,
            label: "Other",
            description: "Write your own response.",
            isCustomResponse: true
        )
    }
}

enum CenteredTranscriptNoteKind: Equatable {
    case interrupted
    case sessionHandoff
    case enteredPlanMode
    case exitedPlanMode
    case stayingInPlanMode
    case contextCompactionStarted
    case contextCompactionCompleted
    case contextCompactionFailed

    var text: String {
        switch self {
        case .interrupted:
            return "Interrupted"
        case .sessionHandoff:
            return "Session handoff"
        case .enteredPlanMode:
            return "Entered plan mode"
        case .exitedPlanMode:
            return "Exited plan mode"
        case .stayingInPlanMode:
            return "Staying in plan mode"
        case .contextCompactionStarted:
            return ConversationContextCompaction.startedDisplayMessage
        case .contextCompactionCompleted:
            return ConversationContextCompaction.completedDisplayMessage
        case .contextCompactionFailed:
            return ConversationContextCompaction.failedDisplayMessage
        }
    }
}

struct ToolEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let input: String
    let output: String?
    let stderr: String?
    let isComplete: Bool
    let isInterrupted: Bool
    let isImage: Bool
    let noOutputExpected: Bool
    let isError: Bool
}

struct SubAgentEntry: Identifiable, Equatable {
    let id: String
    var agentType: String
    var description: String
    var statusDescription: String?
    var lastToolName: String?
    var tools: [ToolEntry]
    var result: String?
    var isComplete: Bool
    var toolUseCount: Int
    var totalTokens: Int = 0
    var durationMs: Int = 0
}

struct PendingSubAgentCompletion: Equatable {
    let toolUses: Int
    let totalTokens: Int
    let durationMs: Int
}

struct TaskEntry: Identifiable, Equatable {
    let id: String
    let content: String
    let activeForm: String?
    var status: Status

    enum Status: String, Equatable {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}

struct ToolApprovalBatchState: Equatable {
    let itemId: String
    let sessionId: String
    let status: ToolApprovalStatus?
}

extension TaskEntry {
    var normalizedContentForMatching: String {
        content.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}

extension ChatItem {
    var isTaskListBlock: Bool {
        if case .taskListBlock = self {
            return true
        }
        return false
    }

    var isIncompleteTaskListBlock: Bool {
        guard case .taskListBlock(_, let tasks) = self else {
            return false
        }
        return tasks.contains { $0.status != .completed }
    }
}
