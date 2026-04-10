import Foundation
import Observation

enum ChatItem: Identifiable, Equatable {
    case userMessage(id: String, text: String)
    case assistantMessage(id: String, text: String)
    case workingBlock(id: String, tools: [ToolEntry])
    case subAgentBlock(id: String, agents: [SubAgentEntry])
    case taskListBlock(id: String, tasks: [TaskEntry])
    case promptBlock(id: String, prompt: PromptEntry)
    case thinking(id: String, text: String)
    case error(id: String, message: String)

    var id: String {
        switch self {
        case .userMessage(let id, _), .assistantMessage(let id, _), .workingBlock(let id, _), .subAgentBlock(let id, _),
             .taskListBlock(let id, _), .promptBlock(let id, _), .thinking(let id, _), .error(let id, _):
            id
        }
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
    }

    struct PromptOption: Equatable {
        let label: String
        let description: String
    }
}

struct ToolEntry: Identifiable, Equatable {
    let id: String
    let name: String
    let summary: String
    let input: String
    let output: String?
    let stderr: String?
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

@MainActor
@Observable
final class ChatItemGrouper {
    private(set) var items: [ChatItem] = []
    private var processedCount = 0
    private var pendingTools: [ToolEntry] = []
    private var workingBlockId: String?
    private var summaryCache: [String: String] = [:]
    private var activeSubAgents: [String: SubAgentEntry] = [:]
    private var pendingSubAgentIds: [String] = []
    private var subAgentIdsReadyForEviction: Set<String> = []
    private var evictedSubAgentIds: Set<String> = []
    private var currentTasks: [TaskEntry] = []
    private var taskListBlockId: String?
    private var promptToolIds: Set<String> = []
    private var subAgentProgressRefreshTask: Task<Void, Never>?

    func update(events: [ConversationEventRecord], forceFullRebuild: Bool = false) {
        if forceFullRebuild || events.count < processedCount {
            resetAllState()
        }

        removeTrailingPendingBlocksIfNeeded()

        for event in events[processedCount...] {
            if routeSubAgentEventIfNeeded(event) {
                continue
            }
            process(event)
        }

        flushTools()
        flushSubAgents()
        processedCount = events.count
    }

    func resetInFlightStateForNewSession() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = nil
        pendingTools = []
        workingBlockId = nil
        summaryCache = [:]
        activeSubAgents = [:]
        pendingSubAgentIds = []
        subAgentIdsReadyForEviction = []
        evictedSubAgentIds = []
        promptToolIds = []
    }

    func markPromptAnswered(promptId: String, summary: String) {
        guard let index = items.lastIndex(where: { item in
            guard case .promptBlock(_, let prompt) = item else {
                return false
            }
            return prompt.id == promptId
        }), case .promptBlock(let id, let prompt) = items[index] else {
            return
        }

        items[index] = .promptBlock(
            id: id,
            prompt: PromptEntry(
                id: prompt.id,
                questions: prompt.questions,
                submittedSummary: summary
            )
        )
    }

    func appendLocalUserMessage(id: String, text: String) {
        flushTools()
        flushSubAgents()
        items.append(.userMessage(id: id, text: text))
        processedCount += 1
    }

    func handleSubAgentControl(_ event: ConversationEvent) {
        switch event {
        case .subAgentStarted(let toolUseId, let description, let taskType):
            if activeSubAgents[toolUseId] == nil {
                let agentType: String
                if taskType == nil || taskType == "local_agent" {
                    agentType = "general-purpose"
                } else {
                    agentType = taskType ?? "general-purpose"
                }
                activeSubAgents[toolUseId] = SubAgentEntry(
                    id: toolUseId,
                    agentType: agentType,
                    description: description,
                    tools: [],
                    result: nil,
                    isComplete: false,
                    toolUseCount: 0
                )
                if !pendingSubAgentIds.contains(toolUseId) {
                    pendingSubAgentIds.append(toolUseId)
                }
            }
            subAgentProgressRefreshTask?.cancel()
            refreshLiveSubAgentBlock()

        case .subAgentProgress(let toolUseId, let description, let lastToolName, let toolUses, let totalTokens, let durationMs):
            mutateSubAgent(id: toolUseId) { subAgent in
                subAgent.statusDescription = description
                subAgent.lastToolName = lastToolName
                subAgent.toolUseCount = toolUses
                subAgent.totalTokens = totalTokens
                subAgent.durationMs = durationMs
            }
            scheduleSubAgentProgressRefresh()

        case .subAgentCompleted(let toolUseId, _, let toolUses, let totalTokens, let durationMs):
            mutateSubAgent(id: toolUseId) { subAgent in
                subAgent.isComplete = true
                subAgent.toolUseCount = toolUses
                subAgent.totalTokens = totalTokens
                subAgent.durationMs = durationMs
            }
            subAgentProgressRefreshTask?.cancel()
            refreshLiveSubAgentBlock()

        default:
            break
        }
    }

    static func toolSummary(name: String?, input: String?) -> String {
        guard let name,
              let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return name ?? "Tool"
        }

        switch name {
        case "Read":
            let path = json["file_path"] as? String ?? ""
            let fileName = (path as NSString).lastPathComponent
            if let offset = json["offset"] as? Int, let limit = json["limit"] as? Int {
                return "Read `\(fileName):\(offset)-\(offset + limit - 1)`"
            }
            return "Read `\(fileName)`"

        case "Edit":
            let path = json["file_path"] as? String ?? ""
            return "Edit `\((path as NSString).lastPathComponent)`"

        case "Write":
            let path = json["file_path"] as? String ?? ""
            return "Write `\((path as NSString).lastPathComponent)`"

        case "Bash":
            let command = json["command"] as? String ?? ""
            let truncated = command.count > 60 ? String(command.prefix(57)) + "..." : command
            return "`\(truncated)`"

        case "Grep":
            return "Grep `\(json["pattern"] as? String ?? "")`"

        case "Glob":
            return "Glob `\(json["pattern"] as? String ?? "")`"

        case "Agent":
            return json["description"] as? String ?? json["subagent_type"] as? String ?? "Sub-agent"

        case "TodoWrite":
            let todos = json["todos"] as? [[String: Any]] ?? []
            let completedCount = todos.filter { ($0["status"] as? String) == "completed" }.count
            return "\(completedCount)/\(todos.count) tasks"

        default:
            return name
        }
    }

    private func routeSubAgentEventIfNeeded(_ event: ConversationEventRecord) -> Bool {
        if let parentToolUseId = event.parentToolUseId, activeSubAgents[parentToolUseId] != nil {
            routeToSubAgent(parentId: parentToolUseId, event: event)
            return true
        }

        if let parentToolUseId = event.parentToolUseId, evictedSubAgentIds.contains(parentToolUseId) {
            return true
        }

        return false
    }

    private func process(_ event: ConversationEventRecord) {
        switch event.type {
        case "message" where event.role == "user":
            flushTools()
            flushSubAgents()
            items.append(.userMessage(id: event.id, text: event.content ?? ""))

        case "message" where event.role == "assistant":
            flushTools()
            flushSubAgents()
            items.append(.assistantMessage(id: event.id, text: event.content ?? ""))

        case "tool_call":
            handleToolCall(event)

        case "tool_result":
            handleToolResult(event)

        case "thinking":
            flushTools()
            items.append(.thinking(id: event.id, text: event.content ?? ""))

        case "error":
            flushTools()
            flushSubAgents()
            items.append(.error(id: event.id, message: event.content ?? "Unknown error"))

        default:
            break
        }
    }

    private func handleToolCall(_ event: ConversationEventRecord) {
        switch event.toolName {
        case "TodoWrite":
            flushTools()
            currentTasks = parseTodoWriteInput(event.toolInput)
            let blockId = taskListBlockId ?? "tasks-\(event.id)"
            taskListBlockId = blockId
            removeLastTaskListBlockIfNeeded()
            items.append(.taskListBlock(id: blockId, tasks: currentTasks))

        case "AskUserQuestion":
            flushTools()
            flushSubAgents()
            let toolId = event.toolId ?? event.id
            promptToolIds.insert(toolId)
            items.append(
                .promptBlock(
                    id: "prompt-\(toolId)",
                    prompt: PromptEntry(
                        id: toolId,
                        questions: parseAskUserQuestionInput(event.toolInput),
                        submittedSummary: event.content?.isEmpty == false ? event.content : nil
                    )
                )
            )

        case "Agent":
            flushTools()
            let toolId = event.toolId ?? event.id
            let parsedInput = parseAgentToolInput(event.toolInput)
            if activeSubAgents[toolId] != nil {
                mutateSubAgent(id: toolId) { subAgent in
                    subAgent.agentType = parsedInput.agentType
                    if !parsedInput.description.isEmpty {
                        subAgent.description = parsedInput.description
                    }
                }
            } else if evictedSubAgentIds.contains(toolId) {
                patchRenderedSubAgentMetadata(
                    id: toolId,
                    agentType: parsedInput.agentType,
                    description: parsedInput.description
                )
            } else {
                activeSubAgents[toolId] = SubAgentEntry(
                    id: toolId,
                    agentType: parsedInput.agentType,
                    description: parsedInput.description,
                    tools: [],
                    result: nil,
                    isComplete: false,
                    toolUseCount: 0
                )
            }
            if !pendingSubAgentIds.contains(toolId) {
                pendingSubAgentIds.append(toolId)
            }

        default:
            if workingBlockId == nil {
                workingBlockId = "work-\(event.id)"
            }
            let toolId = event.toolId ?? event.id
            pendingTools.append(
                ToolEntry(
                    id: toolId,
                    name: event.toolName ?? "Tool",
                    summary: cachedToolSummary(toolId: toolId, name: event.toolName, input: event.toolInput),
                    input: event.toolInput ?? "{}",
                    output: nil,
                    stderr: nil,
                    isInterrupted: false,
                    isImage: false,
                    noOutputExpected: false,
                    isError: false
                )
            )
        }
    }

    private func resetAllState() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = nil
        items = []
        processedCount = 0
        pendingTools = []
        workingBlockId = nil
        summaryCache = [:]
        activeSubAgents = [:]
        pendingSubAgentIds = []
        subAgentIdsReadyForEviction = []
        evictedSubAgentIds = []
        currentTasks = []
        taskListBlockId = nil
        promptToolIds = []
    }

    private func removeTrailingPendingBlocksIfNeeded() {
        if !pendingTools.isEmpty,
           let index = items.lastIndex(where: { item in
               if case .workingBlock = item { return true }
               return false
           }) {
            items.remove(at: index)
        }

        if !pendingSubAgentIds.isEmpty,
           let index = items.lastIndex(where: { item in
               if case .subAgentBlock = item { return true }
               return false
           }) {
            items.remove(at: index)
        }
    }

    private func removeLastTaskListBlockIfNeeded() {
        if let index = items.lastIndex(where: { item in
            if case .taskListBlock = item { return true }
            return false
        }) {
            items.remove(at: index)
        }
    }

    private func handleToolResult(_ event: ConversationEventRecord) {
        if let toolId = event.toolId, promptToolIds.contains(toolId) {
            return
        }

        if let toolId = event.toolId, activeSubAgents[toolId] != nil {
            mutateSubAgent(id: toolId) { subAgent in
                subAgent.result = event.toolOutput ?? event.content
                subAgent.isComplete = true
            }
            subAgentIdsReadyForEviction.insert(toolId)
            return
        }

        if let toolId = event.toolId, evictedSubAgentIds.contains(toolId) {
            patchRenderedSubAgentResult(id: toolId, result: event.toolOutput ?? event.content)
            return
        }

        guard let toolId = event.toolId else {
            return
        }

        let updatedTool = makeCompletedToolEntry(for: toolId, event: event)

        if let pendingIndex = pendingTools.firstIndex(where: { $0.id == toolId }) {
            pendingTools[pendingIndex] = updatedTool ?? pendingTools[pendingIndex]
            return
        }

        patchRenderedToolResult(id: toolId, entry: updatedTool)
    }

    private func makeCompletedToolEntry(for toolId: String, event: ConversationEventRecord) -> ToolEntry? {
        if let pendingIndex = pendingTools.firstIndex(where: { $0.id == toolId }) {
            let pendingTool = pendingTools[pendingIndex]
            return ToolEntry(
                id: pendingTool.id,
                name: pendingTool.name,
                summary: pendingTool.summary,
                input: pendingTool.input,
                output: event.toolOutput ?? event.content,
                stderr: event.toolOutputStderr,
                isInterrupted: event.toolOutputInterrupted,
                isImage: event.toolOutputIsImage,
                noOutputExpected: event.toolOutputNoOutputExpected,
                isError: event.isError
            )
        }

        for item in items.reversed() {
            guard case .workingBlock(_, let tools) = item,
                  let tool = tools.first(where: { $0.id == toolId }) else {
                continue
            }
            return ToolEntry(
                id: tool.id,
                name: tool.name,
                summary: tool.summary,
                input: tool.input,
                output: event.toolOutput ?? event.content,
                stderr: event.toolOutputStderr,
                isInterrupted: event.toolOutputInterrupted,
                isImage: event.toolOutputIsImage,
                noOutputExpected: event.toolOutputNoOutputExpected,
                isError: event.isError
            )
        }

        return nil
    }

    private func mutateSubAgent(id: String, _ mutate: (inout SubAgentEntry) -> Void) {
        guard var subAgent = activeSubAgents[id] else {
            return
        }
        mutate(&subAgent)
        activeSubAgents[id] = subAgent
    }

    private func routeToSubAgent(parentId: String, event: ConversationEventRecord) {
        switch event.type {
        case "tool_call":
            let toolId = event.toolId ?? event.id
            mutateSubAgent(id: parentId) { subAgent in
                subAgent.tools.append(
                    ToolEntry(
                        id: toolId,
                        name: event.toolName ?? "Tool",
                        summary: cachedToolSummary(toolId: toolId, name: event.toolName, input: event.toolInput),
                        input: event.toolInput ?? "{}",
                        output: nil,
                        stderr: nil,
                        isInterrupted: false,
                        isImage: false,
                        noOutputExpected: false,
                        isError: false
                    )
                )
            }

        case "tool_result":
            guard let toolId = event.toolId else {
                return
            }
            mutateSubAgent(id: parentId) { subAgent in
                guard let toolIndex = subAgent.tools.firstIndex(where: { $0.id == toolId }) else {
                    return
                }
                let tool = subAgent.tools[toolIndex]
                subAgent.tools[toolIndex] = ToolEntry(
                    id: tool.id,
                    name: tool.name,
                    summary: tool.summary,
                    input: tool.input,
                    output: event.toolOutput ?? event.content,
                    stderr: event.toolOutputStderr,
                    isInterrupted: event.toolOutputInterrupted,
                    isImage: event.toolOutputIsImage,
                    noOutputExpected: event.toolOutputNoOutputExpected,
                    isError: event.isError
                )
            }

        default:
            break
        }
    }

    private func flushTools() {
        guard !pendingTools.isEmpty else {
            return
        }
        items.append(.workingBlock(id: workingBlockId ?? UUID().uuidString, tools: pendingTools))
        pendingTools = []
        workingBlockId = nil
    }

    private func flushSubAgents() {
        guard !pendingSubAgentIds.isEmpty else {
            return
        }
        let agents = pendingSubAgentIds.compactMap { activeSubAgents[$0] }
        if let firstAgent = agents.first {
            items.append(.subAgentBlock(id: "subagents-\(firstAgent.id)", agents: agents))
        }

        var stillPending: [String] = []
        for id in pendingSubAgentIds {
            if subAgentIdsReadyForEviction.contains(id) {
                activeSubAgents.removeValue(forKey: id)
                subAgentIdsReadyForEviction.remove(id)
                evictedSubAgentIds.insert(id)
            } else {
                stillPending.append(id)
            }
        }
        pendingSubAgentIds = stillPending
    }

    private func refreshLiveSubAgentBlock() {
        if !pendingSubAgentIds.isEmpty,
           let index = items.lastIndex(where: { item in
               if case .subAgentBlock = item { return true }
               return false
           }) {
            items.remove(at: index)
        }
        flushSubAgents()
    }

    private func scheduleSubAgentProgressRefresh() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else {
                return
            }
            refreshLiveSubAgentBlock()
        }
    }

    private func patchRenderedSubAgentMetadata(id: String, agentType: String, description: String) {
        for index in items.indices.reversed() {
            guard case .subAgentBlock(let blockId, var agents) = items[index],
                  let agentIndex = agents.firstIndex(where: { $0.id == id }) else {
                continue
            }
            agents[agentIndex].agentType = agentType
            if !description.isEmpty {
                agents[agentIndex].description = description
            }
            items[index] = .subAgentBlock(id: blockId, agents: agents)
            return
        }
    }

    private func patchRenderedSubAgentResult(id: String, result: String?) {
        for index in items.indices.reversed() {
            guard case .subAgentBlock(let blockId, var agents) = items[index],
                  let agentIndex = agents.firstIndex(where: { $0.id == id }) else {
                continue
            }
            agents[agentIndex].result = result
            items[index] = .subAgentBlock(id: blockId, agents: agents)
            return
        }
    }

    private func patchRenderedToolResult(id: String, entry: ToolEntry?) {
        guard let entry else {
            return
        }

        for index in items.indices.reversed() {
            guard case .workingBlock(let blockId, var tools) = items[index],
                  let toolIndex = tools.firstIndex(where: { $0.id == id }) else {
                continue
            }
            tools[toolIndex] = entry
            items[index] = .workingBlock(id: blockId, tools: tools)
            return
        }
    }

    private func parseTodoWriteInput(_ input: String?) -> [TaskEntry] {
        guard let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let todos = json["todos"] as? [[String: Any]] else {
            return []
        }

        return todos.enumerated().compactMap { index, todo in
            guard let content = todo["content"] as? String else {
                return nil
            }
            let status = TaskEntry.Status(rawValue: todo["status"] as? String ?? "pending") ?? .pending
            return TaskEntry(
                id: "task-\(index)",
                content: content,
                activeForm: todo["activeForm"] as? String,
                status: status
            )
        }
    }

    private func parseAgentToolInput(_ input: String?) -> (agentType: String, description: String) {
        guard let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ("general-purpose", "")
        }
        return (
            json["subagent_type"] as? String ?? "general-purpose",
            json["description"] as? String ?? json["prompt"] as? String ?? ""
        )
    }

    private func parseAskUserQuestionInput(_ input: String?) -> [PromptEntry.PromptQuestion] {
        guard let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = json["questions"] as? [[String: Any]] else {
            return []
        }

        return questions.compactMap { question in
            guard let text = question["question"] as? String else {
                return nil
            }
            let options = (question["options"] as? [[String: Any]] ?? []).compactMap { option -> PromptEntry.PromptOption? in
                guard let label = option["label"] as? String else {
                    return nil
                }
                return PromptEntry.PromptOption(
                    label: label,
                    description: option["description"] as? String ?? ""
                )
            }
            return PromptEntry.PromptQuestion(
                question: text,
                header: question["header"] as? String,
                options: options,
                multiSelect: question["multiSelect"] as? Bool ?? false
            )
        }
    }

    private func cachedToolSummary(toolId: String, name: String?, input: String?) -> String {
        if let cachedSummary = summaryCache[toolId] {
            return cachedSummary
        }
        let summary = Self.toolSummary(name: name, input: input)
        summaryCache[toolId] = summary
        return summary
    }
}
