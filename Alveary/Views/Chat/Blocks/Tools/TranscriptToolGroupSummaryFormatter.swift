import Foundation

enum TranscriptToolGroupSummaryFormatter {
    static func joinedSummaries(_ summaries: [String]) -> String {
        guard let first = summaries.first else {
            return ""
        }
        guard summaries.count > 1 else {
            return first
        }

        let tail = summaries.dropFirst().map(lowercasedFirstLetter)
        if tail.count == 1, let last = tail.first {
            return "\(first) and \(last)"
        }

        return ([first] + tail.dropLast()).joined(separator: ", ") + ", and \(tail.last ?? "")"
    }

    static func lowercasedFirstLetter(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }

    static func toolCategoryKey(for toolName: String) -> String {
        if CommandToolPresentation.isCommandToolName(toolName) {
            return "Command"
        }
        let knownCategories = [
            "LS": "LS",
            "Read": "Read",
            "Grep": "Search",
            "Glob": "Search",
            "WebFetch": "WebFetch",
            "WebSearch": "WebSearch",
            "ToolSearch": "ToolSearch",
            "Write": "Write",
            "Edit": "Edit",
            "MultiEdit": "Edit",
            "NotebookEdit": "Edit",
            "Skill": "Skill"
        ]
        return knownCategories[toolName] ?? (toolName.hasPrefix("mcp__") ? "MCP" : "Tool")
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func toolCategorySummary(for categoryKey: String, count: Int, isComplete: Bool = false) -> String {
        switch categoryKey {
        case "Command":
            return count == 1
                ? (isComplete ? "Ran 1 command" : "Running 1 command")
                : (isComplete ? "Ran \(count) commands" : "Running \(count) commands")
        case "LS":
            return isComplete ? "Listed files" : "Listing files"
        case "Read":
            return count == 1
                ? (isComplete ? "Read 1 file" : "Reading 1 file")
                : (isComplete ? "Read \(count) files" : "Reading \(count) files")
        case "Search":
            return isComplete ? "Searched code" : "Searching code"
        case "ToolSearch":
            return count == 1
                ? (isComplete ? "Searched for 1 tool" : "Searching for 1 tool")
                : (isComplete ? "Searched for \(count) tools" : "Searching for \(count) tools")
        case "WebFetch":
            return isComplete ? "Fetched from the web" : "Fetching from the web"
        case "WebSearch":
            return isComplete ? "Searched the web" : "Searching the web"
        case "MCP":
            return count == 1
                ? (isComplete ? "Ran 1 MCP call" : "Running 1 MCP call")
                : (isComplete ? "Ran \(count) MCP calls" : "Running \(count) MCP calls")
        case "Write":
            return count == 1
                ? (isComplete ? "Wrote 1 file" : "Writing 1 file")
                : (isComplete ? "Wrote \(count) files" : "Writing \(count) files")
        case "Edit":
            return count == 1
                ? (isComplete ? "Edited 1 file" : "Editing 1 file")
                : (isComplete ? "Edited \(count) files" : "Editing \(count) files")
        case "Skill":
            return count == 1
                ? (isComplete ? "Invoked 1 skill" : "Invoking 1 skill")
                : (isComplete ? "Invoked \(count) skills" : "Invoking \(count) skills")
        default:
            return count == 1
                ? (isComplete ? "Ran 1 tool" : "Running 1 tool")
                : (isComplete ? "Ran \(count) tools" : "Running \(count) tools")
        }
    }

    static func subAgentSummary(count: Int, isComplete: Bool) -> String {
        count == 1
            ? (isComplete ? "Explored 1 sub-agent" : "Exploring 1 sub-agent")
            : (isComplete ? "Explored \(count) sub-agents" : "Exploring \(count) sub-agents")
    }
}
