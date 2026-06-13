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

    var visibleTranscriptItems: [ChatItem] {
        filter(\.isVisibleInTranscript)
    }

    var interruptedToolsTerminalized: [ChatItem] {
        let terminalizationStart = lastIndex(where: \.isUserMessage).map { index(after: $0) } ?? startIndex
        return indices.map { index in
            let item = self[index]
            guard index >= terminalizationStart else {
                return item
            }
            switch item {
            case .toolGroup(let id, let tools):
                return .toolGroup(id: id, tools: tools.map(\.terminalizingAsInterruptedIfNeeded))
            case .standaloneTool(let id, let tool):
                return .standaloneTool(id: id, tool: tool.terminalizingAsInterruptedIfNeeded)
            default:
                return item
            }
        }
    }

    var currentTurnItems: ArraySlice<ChatItem> {
        let startIndex = lastIndex(where: \.isUserMessage).map { index(after: $0) } ?? startIndex
        return self[startIndex...]
    }

    var containsCurrentTurnTranscriptError: Bool {
        currentTurnItems.contains {
            if case .error = $0 {
                return true
            }
            return false
        }
    }

    var containsCurrentTurnAssistantMessage: Bool {
        currentTurnItems.contains(where: \.isAssistantMessage)
    }

    func hasEquivalentCurrentTurnError(message: String) -> Bool {
        currentTurnItems.contains { item in
            guard case .error(_, let existingMessage) = item else {
                return false
            }
            return ConversationErrorDisplayPolicy.messagesMatch(existingMessage, message)
        }
    }

    mutating func removeEquivalentCurrentTurnAssistantMessages(message: String) {
        let searchRange = currentTurnSearchRange()
        let matchingIndices = indices.filter { index in
            guard searchRange.contains(index),
                  case .assistantMessage(_, let existingMessage) = self[index] else {
                return false
            }
            return ConversationErrorDisplayPolicy.messagesMatch(existingMessage, message)
        }

        for index in matchingIndices.reversed() {
            remove(at: index)
        }
    }

    private func currentTurnSearchRange() -> Range<Array<ChatItem>.Index> {
        let rangeStart = lastIndex(where: \.isUserMessage).map { index(after: $0) } ?? startIndex
        return rangeStart..<endIndex
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

enum ToolContentPreviewOrigin: Equatable {
    case knownMarkdownMutation
    case exitPlanModeFollowUp
}

struct SubAgentCompletionMarkerPayload: Codable, Equatable {
    let status: String?
    let toolUses: Int
    let totalTokens: Int
}

enum SubAgentCompletionDisposition: Equatable {
    case success
    case failed
    case interrupted
    case neutral

    init(status: String?) {
        guard let status = status?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !status.isEmpty else {
            self = .success
            return
        }

        switch status {
        case "completed", "success", "succeeded":
            self = .success
        case "failed", "error":
            self = .failed
        case "cancelled", "canceled", "interrupted":
            self = .interrupted
        default:
            self = .neutral
        }
    }
}

struct ToolContentPreview: Equatable {
    let content: String
    let language: String
    let baseURL: URL?
    let origin: ToolContentPreviewOrigin

    init(
        content: String,
        language: String,
        baseURL: URL?,
        origin: ToolContentPreviewOrigin = .knownMarkdownMutation
    ) {
        self.content = content
        self.language = language
        self.baseURL = baseURL
        self.origin = origin
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
    let previewOverride: ToolContentPreview?

    init(
        id: String,
        name: String,
        summary: String,
        input: String,
        output: String?,
        stderr: String?,
        isComplete: Bool,
        isInterrupted: Bool,
        isImage: Bool,
        noOutputExpected: Bool,
        isError: Bool,
        previewOverride: ToolContentPreview? = nil
    ) {
        self.id = id
        self.name = name
        self.summary = summary
        self.input = input
        self.output = output
        self.stderr = stderr
        self.isComplete = isComplete
        self.isInterrupted = isInterrupted
        self.isImage = isImage
        self.noOutputExpected = noOutputExpected
        self.isError = isError
        self.previewOverride = previewOverride
    }
}

extension ToolEntry {
    var terminalizingAsInterruptedIfNeeded: ToolEntry {
        guard !isComplete else {
            return self
        }
        return ToolEntry(
            id: id,
            name: name,
            summary: summary,
            input: input,
            output: output,
            stderr: stderr,
            isComplete: true,
            isInterrupted: true,
            isImage: isImage,
            noOutputExpected: noOutputExpected,
            isError: isError,
            previewOverride: previewOverride
        )
    }
}

enum CommandToolPresentation {
    static let rowSummaryCommandLimit = 60

    static func isCommandToolName(_ name: String) -> Bool {
        switch name {
        case "Bash", "CommandExecution":
            return true
        default:
            return false
        }
    }

    static func command(fromInput input: String?) -> String? {
        guard let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        return command(fromJSON: json)
    }

    static func command(fromJSON json: [String: Any]) -> String? {
        guard let command = json["command"] as? String else {
            return nil
        }
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedCommand.isEmpty ? nil : trimmedCommand
    }

    static func executingSummary(command: String) -> String {
        "Executing \(summaryBody(command: command))"
    }

    static func summaryBody(command: String) -> String {
        "`\(truncated(command, limit: rowSummaryCommandLimit))`"
    }

    static func summaryBody(from summary: String) -> String {
        summary
            .replacingPrefix("Denied ", with: "")
            .replacingPrefix("Executing ", with: "")
            .replacingPrefix("Running ", with: "")
            .replacingPrefix("Ran ", with: "")
    }

    private static func truncated(_ value: String, limit: Int) -> String {
        guard value.count > limit else {
            return value
        }
        return String(value.prefix(limit - 3)) + "..."
    }
}

private extension String {
    func replacingPrefix(_ prefix: String, with replacement: String) -> String {
        guard hasPrefix(prefix) else {
            return self
        }
        return replacement + String(dropFirst(prefix.count))
    }
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
    var completionDisposition: SubAgentCompletionDisposition = .success
}

struct PendingSubAgentCompletion: Equatable {
    let toolUses: Int
    let totalTokens: Int
    let durationMs: Int
    let disposition: SubAgentCompletionDisposition
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
    var isVisibleInTranscript: Bool {
        guard case .promptBlock(_, let prompt) = self else {
            return true
        }
        guard let submittedSummary = prompt.submittedSummary else {
            return true
        }
        return submittedSummary != ChatItemGrouper.handledPromptSummary
    }

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
