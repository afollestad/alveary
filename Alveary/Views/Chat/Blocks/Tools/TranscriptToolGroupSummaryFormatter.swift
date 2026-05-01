import Foundation

enum TranscriptToolGroupSummaryFormatter {
    static func lowercasedFirstLetter(_ text: String) -> String {
        guard let first = text.first else {
            return text
        }
        return first.lowercased() + text.dropFirst()
    }

    static func toolCategoryKey(for toolName: String) -> String {
        switch toolName {
        case "Read":
            return "Read"
        case "Grep", "Glob":
            return "Search"
        case "WebFetch":
            return "WebFetch"
        case "WebSearch":
            return "WebSearch"
        case "ToolSearch":
            return "ToolSearch"
        default:
            return toolName.hasPrefix("mcp__") ? "MCP" : toolName
        }
    }

    static func toolCategorySummary(for categoryKey: String, count: Int, isComplete: Bool = false) -> String {
        switch categoryKey {
        case "Read":
            return count == 1
                ? (isComplete ? "Read 1 file" : "Reading 1 file")
                : (isComplete ? "Read \(count) files" : "Reading \(count) files")
        case "Search":
            return count == 1
                ? (isComplete ? "Searched for 1 pattern" : "Searching for 1 pattern")
                : (isComplete ? "Searched for \(count) patterns" : "Searching for \(count) patterns")
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
        default:
            return count == 1 ? categoryKey : "\(categoryKey) x\(count)"
        }
    }
}
