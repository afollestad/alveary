# Part 2b: Event Grouping

Raw events to renderable ChatItems. Pure data transformation. Continues from Part 2a.

## Event Grouping

Raw `ConversationEventRecord`s are grouped into renderable `ChatItem`s. This is pure data transformation with no view or service dependencies — it belongs here (Part 2) because `ConversationState` stores a `ChatItemGrouper` instance.

```swift
/// A single renderable chat item, produced by grouping sequential ConversationEventRecords.
enum ChatItem: Identifiable {  // Skep/Services/Agent/ChatItemGrouper.swift
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
        case .userMessage(let id, _), .assistantMessage(let id, _),
             .workingBlock(let id, _), .subAgentBlock(let id, _),
             .taskListBlock(let id, _), .promptBlock(let id, _),
             .thinking(let id, _), .error(let id, _): return id
        }
    }
}

/// Data snapshot of an AskUserQuestion tool_call. The app renders a native selection UI;
/// selection state lives in `@State` on the `PromptBlock` view, not here.
struct PromptEntry: Identifiable {  // Skep/Services/Agent/ChatItemGrouper.swift
    let id: String                  // toolId
    let questions: [PromptQuestion]
    let submittedSummary: String?   // persisted compact answer summary once the user responds

    struct PromptQuestion {
        let question: String
        let header: String?         // short label (e.g. "Framework")
        let options: [PromptOption]
        let multiSelect: Bool
    }

    struct PromptOption {
        let label: String
        let description: String
    }
}

/// One tool call + its result within a working block.
struct ToolEntry: Identifiable {  // Skep/Services/Agent/ChatItemGrouper.swift
    let id: String          // toolId
    let name: String        // e.g. "Bash", "Edit", "Read"
    let summary: String     // e.g. "git status", "src/auth.swift:10-50"
    let input: String       // raw JSON input
    let output: String?     // stdout / primary tool output; nil if still in progress
    let stderr: String?
    let isInterrupted: Bool
    let isImage: Bool
    let noOutputExpected: Bool
    let isError: Bool
}

/// A sub-agent spawned via the "Agent" tool. Groups events sharing the same parentToolUseId.
struct SubAgentEntry: Identifiable {  // Skep/Services/Agent/ChatItemGrouper.swift
    let id: String              // Agent tool_use id (parentToolUseId)
    var agentType: String       // canonical subtype from Agent tool input when available (e.g. "Explore", "Plan")
    var description: String     // canonical description from Agent tool input
    var statusDescription: String?  // live status from task_progress
    var lastToolName: String?   // most recent tool (from task_progress)
    var tools: [ToolEntry]      // inner tool calls
    var result: String?         // nil while still running
    var isComplete: Bool
    var toolUseCount: Int        // live via task_progress, finalized via task_notification
    var totalTokens: Int = 0    // live via task_progress, finalized via task_notification
    var durationMs: Int = 0     // live via task_progress
}

/// A task from the TodoWrite tool. Each call contains the full list (replaces, not appends).
/// CLI does NOT send `id` — generated from array index for Identifiable conformance.
struct TaskEntry: Identifiable {  // Skep/Services/Agent/ChatItemGrouper.swift
    let id: String              // e.g. "task-0", "task-1"
    let content: String         // task description
    let activeForm: String?     // present-continuous spinner label (e.g. "Checking if tests pass")
    var status: Status

    enum Status: String {
        case pending
        case inProgress = "in_progress"
        case completed
    }
}
```

The `ChatItemGrouper` incrementally processes `@Query` results into renderable `ChatItem`s. It tracks how many events have been processed and only scans new events on each update:

```swift
/// Incremental grouping cache. Tracks processed count; only scans new events on each update.
/// Sub-agent events (parentToolUseId != nil) are routed into SubAgentEntry objects.
@MainActor @Observable
class ChatItemGrouper {  // Skep/Services/Agent/ChatItemGrouper.swift
    private(set) var items: [ChatItem] = []
    private var processedCount: Int = 0
    private var pendingTools: [ToolEntry] = []
    private var workingBlockId: String?
    /// Tool summary cache keyed by toolId (avoids re-parsing JSON).
    private var summaryCache: [String: String] = [:]
    /// Sub-agent lifecycle: activeSubAgents → pendingSubAgentIds → flushed into
    /// items as .subAgentBlock → completed agents evicted to evictedSubAgentIds.
    /// Late inner events are discarded once a sub-agent is evicted, but later persisted
    /// top-level metadata/results for the same tool ID still patch the rendered block in
    /// place instead of recreating a duplicate sub-agent.
    private var activeSubAgents: [String: SubAgentEntry] = [:]
    /// Ordered pending sub-agent IDs (flushed like tools).
    private var pendingSubAgentIds: [String] = []
    /// Completed sub-agents stay live until the top-level Agent tool_result arrives,
    /// so late persisted inner tool rows are still routed into the finished block.
    private var subAgentIdsReadyForEviction: Set<String> = []
    /// Evicted sub-agent IDs — used to suppress duplicate recreation after a fast live
    /// completion, while still allowing targeted metadata/result patching into the already
    /// rendered block. Grows ~30 chars per completed sub-agent; negligible for typical
    /// sessions. Cleared on rebuild.
    private var evictedSubAgentIds: Set<String> = []
    /// Current task list (replaced in full on each TodoWrite).
    private var currentTasks: [TaskEntry] = []
    /// ID of the task list block in items[] (for replace-in-place on subsequent TodoWrite calls).
    private var taskListBlockId: String?
    /// Tool IDs of AskUserQuestion tool_calls that produced prompt blocks.
    /// Used for O(1) suppression of auto-denied tool_results (avoids scanning items[]).
    private var promptToolIds: Set<String> = []
    /// Coalesces frequent sub-agent progress churn so the tail block is not re-built on
    /// every single progress event. Started/completed still refresh immediately.
    private var subAgentProgressRefreshTask: Task<Void, Never>?

    /// Processes new events since last call. Pass `forceFullRebuild: true` if events were
    /// deleted/reordered or if existing records were mutated in place without a targeted
    /// updater (for example a future non-prompt field edit).
    func update(events: [ConversationEventRecord], forceFullRebuild: Bool = false) {
        if forceFullRebuild || events.count < processedCount {
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

        // Remove trailing pending blocks — new events may complete or extend them.
        if !pendingTools.isEmpty, let lastIdx = items.lastIndex(where: {
            if case .workingBlock = $0 { return true } else { return false }
        }) {
            items.remove(at: lastIdx)
        }
        if !pendingSubAgentIds.isEmpty, let lastIdx = items.lastIndex(where: {
            if case .subAgentBlock = $0 { return true } else { return false }
        }) {
            items.remove(at: lastIdx)
        }

        let newEvents = events[processedCount...]
        for event in newEvents {
            // Route sub-agent inner events
            if let parentId = event.parentToolUseId, activeSubAgents[parentId] != nil {
                routeToSubAgent(parentId: parentId, event: event)
                continue
            }
            // Discard late events for evicted sub-agents (prevents top-level misclassification).
            if let parentId = event.parentToolUseId, evictedSubAgentIds.contains(parentId) {
                continue
            }

            switch event.type {
            case "message" where event.role == "user":
                flushTools()
                flushSubAgents()
                items.append(.userMessage(id: event.id, text: event.content ?? ""))

            case "message" where event.role == "assistant":
                flushTools()
                flushSubAgents()
                items.append(.assistantMessage(id: event.id, text: event.content ?? ""))

            case "tool_call" where event.toolName == "TodoWrite":
                // Float-to-bottom: remove old block and re-append at tail (task list stays below working blocks).
                flushTools()
                currentTasks = parseTodoWriteInput(event.toolInput)
                let blockId = taskListBlockId ?? "tasks-\(event.id)"
                taskListBlockId = blockId
                if let existingIdx = items.lastIndex(where: {
                    if case .taskListBlock = $0 { return true } else { return false }
                }) {
                    items.remove(at: existingIdx)
                }
                items.append(.taskListBlock(id: blockId, tasks: currentTasks))

            case "tool_call" where event.toolName == "AskUserQuestion":
                // Render native selection UI; the auto-denied tool_result is suppressed below.
                flushTools()
                flushSubAgents()
                let toolId = event.toolId ?? event.id
                promptToolIds.insert(toolId)
                let prompt = parseAskUserQuestionInput(event.toolInput)
                items.append(.promptBlock(id: "prompt-\(toolId)", prompt: PromptEntry(
                    id: toolId,
                    questions: prompt,
                    submittedSummary: event.content?.isEmpty == false ? event.content : nil
                )))

            case "tool_call" where event.toolName == "Agent":
                // Backfill canonical subtype/description from the persisted Agent tool_call.
                // Live task_started currently arrives first and only carries a generic
                // `task_type` such as "local_agent", so the tool input is authoritative.
                flushTools()
                let toolId = event.toolId ?? event.id
                let (agentType, description) = parseAgentToolInput(event.toolInput)
                if var existing = activeSubAgents[toolId] {
                    existing.agentType = agentType
                    if !description.isEmpty { existing.description = description }
                    activeSubAgents[toolId] = existing
                } else if evictedSubAgentIds.contains(toolId) {
                    patchRenderedSubAgentMetadata(id: toolId, agentType: agentType, description: description)
                } else {
                    activeSubAgents[toolId] = SubAgentEntry(
                        id: toolId,
                        agentType: agentType,
                        description: description,
                        tools: [],
                        result: nil,
                        isComplete: false,
                        toolUseCount: 0
                    )
                }
                if !pendingSubAgentIds.contains(toolId) {
                    pendingSubAgentIds.append(toolId)
                }

            case "tool_call":
                if workingBlockId == nil { workingBlockId = "work-\(event.id)" }
                let toolId = event.toolId ?? event.id
                let summary = cachedToolSummary(toolId: toolId, name: event.toolName, input: event.toolInput)
                pendingTools.append(ToolEntry(
                    id: toolId,
                    name: event.toolName ?? "Tool",
                    summary: summary,
                    input: event.toolInput ?? "{}",
                    output: nil,
                    stderr: nil,
                    isInterrupted: false,
                    isImage: false,
                    noOutputExpected: false,
                    isError: false
                ))

            case "tool_result":
                // Suppress the auto-denied AskUserQuestion result (promptBlock already rendered it).
                if let toolId = event.toolId, promptToolIds.contains(toolId) {
                    break
                }
                // Sub-agent completion
                if let toolId = event.toolId, activeSubAgents[toolId] != nil {
                    activeSubAgents[toolId]?.result = event.toolOutput ?? event.content
                    activeSubAgents[toolId]?.isComplete = true
                    subAgentIdsReadyForEviction.insert(toolId)
                } else if let toolId = event.toolId, evictedSubAgentIds.contains(toolId) {
                    // Late result for evicted sub-agent — update in-place (handleSubAgentControl sets isComplete but not result).
                    for blockIdx in items.indices.reversed() {
                        guard case .subAgentBlock(let id, var agents) = items[blockIdx],
                              let agentIdx = agents.firstIndex(where: { $0.id == toolId })
                        else { continue }
                        agents[agentIdx].result = event.toolOutput ?? event.content
                        items[blockIdx] = .subAgentBlock(id: id, agents: agents)
                        break
                    }
                } else if let toolId = event.toolId,
                          let idx = pendingTools.firstIndex(where: { $0.id == toolId }) {
                    pendingTools[idx] = ToolEntry(
                        id: pendingTools[idx].id,
                        name: pendingTools[idx].name,
                        summary: pendingTools[idx].summary,
                        input: pendingTools[idx].input,
                        output: event.toolOutput ?? event.content,
                        stderr: event.toolOutputStderr,
                        isInterrupted: event.toolOutputInterrupted,
                        isImage: event.toolOutputIsImage,
                        noOutputExpected: event.toolOutputNoOutputExpected,
                        isError: event.isError
                    )
                } else if let toolId = event.toolId {
                    // Tool already flushed — scan all workingBlocks in reverse to update in-place.
                    for blockIdx in items.indices.reversed() {
                        guard case .workingBlock(let id, var tools) = items[blockIdx],
                              let toolIdx = tools.firstIndex(where: { $0.id == toolId })
                        else { continue }
                        tools[toolIdx] = ToolEntry(
                            id: tools[toolIdx].id,
                            name: tools[toolIdx].name,
                            summary: tools[toolIdx].summary,
                            input: tools[toolIdx].input,
                            output: event.toolOutput ?? event.content,
                            stderr: event.toolOutputStderr,
                            isInterrupted: event.toolOutputInterrupted,
                            isImage: event.toolOutputIsImage,
                            noOutputExpected: event.toolOutputNoOutputExpected,
                            isError: event.isError
                        )
                        items[blockIdx] = .workingBlock(id: id, tools: tools)
                        break
                    }
                }

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
        flushTools()
        flushSubAgents()
        processedCount = events.count
    }

    /// Clears only session-scoped transient state before a forked-session re-subscribe.
    /// Durable rendered history in `items` stays intact so the chat does not blank out
    /// while the next persisted event from the new session is still pending.
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

    /// Updates an existing prompt block after the backing tool_call row is mutated in-place.
    /// Avoids refetching the full conversation or forcing a full regroup for a one-row change.
    func markPromptAnswered(promptId: String, summary: String) {
        guard let idx = items.lastIndex(where: {
            guard case .promptBlock(_, let prompt) = $0 else { return false }
            return prompt.id == promptId
        }), case .promptBlock(let id, let prompt) = items[idx] else {
            return
        }
        items[idx] = .promptBlock(id: id, prompt: PromptEntry(
            id: prompt.id,
            questions: prompt.questions,
            submittedSummary: summary
        ))
    }

    /// Routes a sub-agent inner event into its SubAgentEntry.
    private func routeToSubAgent(parentId: String, event: ConversationEventRecord) {
        switch event.type {
        case "tool_call":
            let toolId = event.toolId ?? event.id
            let summary = cachedToolSummary(toolId: toolId, name: event.toolName, input: event.toolInput)
            activeSubAgents[parentId]?.tools.append(ToolEntry(
                id: toolId,
                name: event.toolName ?? "Tool",
                summary: summary,
                input: event.toolInput ?? "{}",
                output: nil,
                stderr: nil,
                isInterrupted: false,
                isImage: false,
                noOutputExpected: false,
                isError: false
            ))
        case "tool_result":
            if let toolId = event.toolId,
               let idx = activeSubAgents[parentId]?.tools.firstIndex(where: { $0.id == toolId }),
               let existing = activeSubAgents[parentId]?.tools[idx] {
                activeSubAgents[parentId]?.tools[idx] = ToolEntry(
                    id: existing.id, name: existing.name, summary: existing.summary,
                    input: existing.input, output: event.toolOutput ?? event.content,
                    stderr: event.toolOutputStderr,
                    isInterrupted: event.toolOutputInterrupted,
                    isImage: event.toolOutputIsImage,
                    noOutputExpected: event.toolOutputNoOutputExpected,
                    isError: event.isError
                )
            }
        case "tokens":
            break  // tracked via task_progress/task_notification instead
        default:
            // Inner thinking/messages not surfaced — summary + result are sufficient.
            break
        }
    }

    private func flushTools() {
        if !pendingTools.isEmpty {
            items.append(.workingBlock(id: workingBlockId ?? UUID().uuidString, tools: pendingTools))
            pendingTools = []
            workingBlockId = nil
        }
    }

    /// Flush pending sub-agents into a single subAgentBlock. In-progress agents stay in
    /// pendingSubAgentIds for re-flush on next update() (avoids stale value-type snapshots).
    /// Completed agents are only evicted after their top-level Agent tool_result arrives;
    /// `task_notification` alone is not enough because persisted inner tool rows may still
    /// arrive afterward and must not be discarded.
    private func flushSubAgents() {
        guard !pendingSubAgentIds.isEmpty else { return }
        let agents = pendingSubAgentIds.compactMap { activeSubAgents[$0] }
        if !agents.isEmpty {
            items.append(.subAgentBlock(id: "subagents-\(agents[0].id)", agents: agents))
        }
        // Evict only entries whose top-level Agent tool_result has arrived. Keep merely
        // completed ones live so late persisted inner events still route into them.
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

    /// Refresh the visible sub-agent block from the current ephemeral state.
    /// `task_started` / `task_progress` / `task_notification` events are not
    /// persisted, so waiting for the next `update(events:)` pass would make the
    /// live sub-agent UI lag behind the stream. Rebuild just the trailing
    /// in-flight sub-agent snapshot here instead.
    private func refreshLiveSubAgentBlock() {
        if !pendingSubAgentIds.isEmpty, let lastIdx = items.lastIndex(where: {
            if case .subAgentBlock = $0 { return true } else { return false }
        }) {
            items.remove(at: lastIdx)
        }
        flushSubAgents()
    }

    private func scheduleSubAgentProgressRefresh() {
        subAgentProgressRefreshTask?.cancel()
        subAgentProgressRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            refreshLiveSubAgentBlock()
        }
    }

    /// Handles live (non-persisted) sub-agent control events from ConversationViewModel.
    func handleSubAgentControl(_ event: ConversationEvent) {
        switch event {
        case .subAgentStarted(let toolUseId, let description, let taskType):
            // Create a provisional entry early for live progress. Do not trust Claude's
            // current `task_type` for the user-facing subtype: validated output reports a
            // generic value like `local_agent`, while the later Agent tool_call carries the
            // canonical `subagent_type` (Explore/Plan/etc.) that patches this entry.
            if activeSubAgents[toolUseId] == nil {
                let provisionalType = (taskType == nil || taskType == "local_agent")
                    ? "general-purpose"
                    : (taskType ?? "general-purpose")
                activeSubAgents[toolUseId] = SubAgentEntry(
                    id: toolUseId,
                    agentType: provisionalType,
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
            activeSubAgents[toolUseId]?.statusDescription = description
            activeSubAgents[toolUseId]?.lastToolName = lastToolName
            activeSubAgents[toolUseId]?.toolUseCount = toolUses
            activeSubAgents[toolUseId]?.totalTokens = totalTokens
            activeSubAgents[toolUseId]?.durationMs = durationMs
            scheduleSubAgentProgressRefresh()
        case .subAgentCompleted(let toolUseId, _, let toolUses, let totalTokens, let durationMs):
            activeSubAgents[toolUseId]?.isComplete = true
            activeSubAgents[toolUseId]?.toolUseCount = toolUses
            activeSubAgents[toolUseId]?.totalTokens = totalTokens
            activeSubAgents[toolUseId]?.durationMs = durationMs
            subAgentProgressRefreshTask?.cancel()
            refreshLiveSubAgentBlock()
        default:
            break
        }
    }

    private func patchRenderedSubAgentMetadata(id: String, agentType: String, description: String) {
        for blockIdx in items.indices.reversed() {
            guard case .subAgentBlock(let blockId, var agents) = items[blockIdx],
                  let agentIdx = agents.firstIndex(where: { $0.id == id })
            else { continue }
            agents[agentIdx].agentType = agentType
            if !description.isEmpty {
                agents[agentIdx].description = description
            }
            items[blockIdx] = .subAgentBlock(id: blockId, agents: agents)
            break
        }
    }

    /// Parses TodoWrite input JSON into TaskEntry values. IDs generated from array index.
    private func parseTodoWriteInput(_ input: String?) -> [TaskEntry] {
        guard let input, let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let todos = json["todos"] as? [[String: Any]]
        else { return [] }
        return todos.enumerated().compactMap { index, todo in
            guard let content = todo["content"] as? String else { return nil }
            let statusStr = todo["status"] as? String ?? "pending"
            let status = TaskEntry.Status(rawValue: statusStr) ?? .pending
            let activeForm = todo["activeForm"] as? String
            return TaskEntry(id: "task-\(index)", content: content, activeForm: activeForm, status: status)
        }
    }

    /// Parses Agent tool input for agentType and description.
    private func parseAgentToolInput(_ input: String?) -> (agentType: String, description: String) {
        guard let input, let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return ("general-purpose", "") }
        let agentType = json["subagent_type"] as? String ?? "general-purpose"
        let description = json["description"] as? String ?? json["prompt"] as? String ?? ""
        return (agentType, description)
    }

    /// Parses AskUserQuestion input JSON into PromptQuestion values.
    private func parseAskUserQuestionInput(_ input: String?) -> [PromptEntry.PromptQuestion] {
        guard let input, let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let questions = json["questions"] as? [[String: Any]]
        else { return [] }
        return questions.compactMap { q in
            guard let questionText = q["question"] as? String else { return nil }
            let header = q["header"] as? String
            let multiSelect = q["multiSelect"] as? Bool ?? false
            let options = (q["options"] as? [[String: Any]] ?? []).compactMap { opt -> PromptEntry.PromptOption? in
                guard let label = opt["label"] as? String else { return nil }
                let description = opt["description"] as? String ?? ""
                return PromptEntry.PromptOption(label: label, description: description)
            }
            return PromptEntry.PromptQuestion(
                question: questionText, header: header,
                options: options, multiSelect: multiSelect
            )
        }
    }

    /// Returns cached summary; parses JSON only on first call per tool.
    private func cachedToolSummary(toolId: String, name: String?, input: String?) -> String {
        if let cached = summaryCache[toolId] { return cached }
        let summary = Self.toolSummary(name: name, input: input)
        summaryCache[toolId] = summary
        return summary
    }

    /// Derives a human-readable summary from tool name and JSON input.
    static func toolSummary(name: String?, input: String?) -> String {
        guard let name, let input,
              let data = input.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return name ?? "Tool" }

        switch name {
        case "Read":
            let path = json["file_path"] as? String ?? ""
            let file = (path as NSString).lastPathComponent
            if let offset = json["offset"] as? Int, let limit = json["limit"] as? Int {
                return "Read `\(file):\(offset)-\(offset + limit - 1)`"
            }
            return "Read `\(file)`"
        case "Edit":
            let path = json["file_path"] as? String ?? ""
            return "Edit `\((path as NSString).lastPathComponent)`"
        case "Write":
            let path = json["file_path"] as? String ?? ""
            return "Write `\((path as NSString).lastPathComponent)`"
        case "Bash":
            let cmd = json["command"] as? String ?? ""
            let truncated = cmd.count > 60 ? String(cmd.prefix(57)) + "..." : cmd
            return "`\(truncated)`"
        case "Grep":
            return "Grep `\(json["pattern"] as? String ?? "")`"
        case "Glob":
            return "Glob `\(json["pattern"] as? String ?? "")`"
        case "Agent":
            let desc = json["description"] as? String ?? json["subagent_type"] as? String ?? "Sub-agent"
            return desc
        case "TodoWrite":
            let todos = json["todos"] as? [[String: Any]] ?? []
            let done = todos.filter { ($0["status"] as? String) == "completed" }.count
            return "\(done)/\(todos.count) tasks"
        default:
            return name
        }
    }
}
```

**Unit tests for ChatItemGrouper (basic grouping):** cover message/tool/thinking/error sequencing and incremental processing. Non-obvious:
- tool_result arriving after flush boundary (separate `update()` call) scans ALL workingBlocks in reverse to find and update the ToolEntry in-place (not just the last block — a newer block may exist for unrelated tools)
- tool_result for an unknown toolId is silently ignored (no crash)
- tool_result metadata (`stderr`, `interrupted`, `isImage`, `noOutputExpected`) survives both the pending-tool path and the late-result scan path
- `events.count < processedCount` triggers automatic full rebuild (event deletion detected)
- Tool summary is cached per toolId (second call returns same value without re-parsing JSON)

**Unit tests for ChatItemGrouper.toolSummary():** cover each known tool name (Read, Edit, Write, Bash, Grep, Glob, Agent). Non-obvious:
- Bash tool truncates command at 60 chars with `...`
- Malformed input JSON falls back to tool name as-is (no crash)

**Unit tests for ChatItemGrouper (sub-agent handling):** cover Agent tool_call/result lifecycle, event routing by `parentToolUseId`, and mixed sequences with direct tools. Non-obvious:
- In-progress sub-agent block is re-flushed on each `update()` with latest state (value-type snapshot must be refreshed)
- `task_notification` marks the sub-agent complete for live UI but does NOT evict it yet; late persisted inner events still route into that completed block until the top-level Agent tool_result arrives
- Once the top-level Agent tool_result arrives, the completed sub-agent is evicted from `activeSubAgents`; later inner events for that evicted ID are silently discarded instead of being misclassified as top-level
- Agent tool_result (with `parentToolUseId == nil`) for an evicted sub-agent scans `subAgentBlock`s in reverse and updates the `SubAgentEntry.result` in-place — result text is NOT dropped
- `forceFullRebuild` resets `evictedSubAgentIds` so a full re-scan doesn't incorrectly discard events

**Unit tests for ChatItemGrouper.handleSubAgentControl():** cover started/progress/completed lifecycle. Non-obvious:
- `subAgentStarted` for an already-existing entry (from Agent tool_call in `update()`) is a no-op — does NOT duplicate
- Agent tool_call in `update()` does NOT overwrite an entry already created by `subAgentStarted` (preserves live status updates)
- `subAgentProgress` / `subAgentCompleted` for unknown or evicted IDs are no-ops
- `subAgentStarted` / `subAgentCompleted` refresh the rendered `.subAgentBlock` immediately, but dense `subAgentProgress` bursts are coalesced (~150ms) so the tail block does not re-render on every single progress event

**Unit tests for ChatItemGrouper (task list handling):** cover TodoWrite parsing, full-replacement semantics, and malformed input. Non-obvious:
- Second TodoWrite floats the task list to the tail (removes old block, re-appends below any intervening working blocks)
- Task `id` is generated from array index ("task-0", "task-1") — CLI does NOT send an `id` field
- Unknown status values default to `.pending`

**Unit tests for ChatItemGrouper (prompt block handling):** cover AskUserQuestion parsing and rendering. Non-obvious:
- AskUserQuestion tool_result (is_error: true, "Answer questions?") is **suppressed** — the auto-denial result must not appear as an error ChatItem
- Persisted `AskUserQuestion` tool_call with `content` populated rebuilds as an answered/read-only prompt block (`submittedSummary`), not as fresh interactive controls
- `markPromptAnswered(promptId:summary:)` updates an existing prompt block in place after the tool_call row is saved, avoiding a full conversation refetch/regroup for that one-row mutation
- `resetInFlightStateForNewSession()` clears `promptToolIds` and `summaryCache` along with other session-scoped transient caches, so a forked session cannot accidentally suppress an unrelated new-session `tool_result` or reuse a stale tool summary if tool IDs are reused
- `forceFullRebuild` preserves prompt blocks (they're append-only, not tracked like tasks/sub-agents)

**Unit tests for ChatItemGrouper (working block / session reset handling):** cover session-fork cache invalidation in addition to normal tool grouping. Non-obvious:
- `resetInFlightStateForNewSession()` clears `summaryCache`, so a new-session tool_call reusing an old tool ID recomputes its summary from the new input instead of showing stale text from the previous session
- `resetInFlightStateForNewSession()` does NOT clear durable `items` or `taskListBlockId`; historical working blocks/task list remain visible until new persisted events replace or extend them

---
