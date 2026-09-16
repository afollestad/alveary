import AgentCLIKit
import Foundation

/// Native tool names share the existing transcript presentations while structured events own prompts and task lists.
extension AgentCLIKitEventMapper {
    func openCodeToolCall(_ event: AgentToolCallEvent) -> AgentToolCallEvent? {
        guard !hidesOpenCodeTool(event.name) else { return nil }
        let name = Self.openCodeToolNames[event.name] ?? event.name
        var input = event.input
        if case .object(var values) = input {
            values["agent_separate_interaction_ids"] = .bool(true)
            if values["file_path"] == nil, let path = values["filePath"] { values["file_path"] = path }
            if values["old_string"] == nil, let old = values["oldString"] { values["old_string"] = old }
            if values["new_string"] == nil, let new = values["newString"] { values["new_string"] = new }
            if event.name == "task" { values["agent_subagent_event"] = .bool(true) }
            input = .object(values)
        }
        return AgentToolCallEvent(id: event.id, name: name, input: input, metadata: event.metadata)
    }

    func hidesOpenCodeTool(_ name: String?) -> Bool {
        // Questions are keyed by the native interaction ID, unlike their containing tool call.
        name == "question" || name == "todowrite"
    }

    private static let openCodeToolNames = [
        "bash": "Bash", "read": "Read", "edit": "Edit", "write": "Write", "glob": "Glob", "grep": "Grep",
        "list": "LS", "webfetch": "WebFetch", "websearch": "WebSearch", "skill": "Skill", "task": "Agent"
    ]
}
