import Foundation

extension ChatItemGrouper {
    enum ToolGroupability {
        case groupable
        case standalone
    }

    /// Decide whether a generic tool call (i.e. not `Agent`, `TodoWrite`, or `AskUserQuestion`
    /// — those are routed to their own block types) belongs in a collapsible `toolGroup` or
    /// should render as a `standaloneTool` row.
    ///
    /// Groupable: read-only, informational tools whose repeated rendering would clutter the
    /// transcript (Read/Grep/Glob/WebFetch/WebSearch and MCP lookup-style calls).
    /// Standalone: mutating, output-heavy, or lifecycle tools the user wants to see per-row
    /// (anything that can render an Alveary approval prompt, plus Skill invocations).
    /// Unknown tools default to standalone so a tool that actually mutates state never gets
    /// silently folded into a group header.
    static func groupability(forToolNamed name: String) -> ToolGroupability {
        if ClaudeHookPolicy.canRenderToolApproval(name) {
            return .standalone
        }

        switch name {
        case "Skill":
            return .standalone
        case "Read", "Grep", "Glob", "WebFetch", "WebSearch", "ToolSearch":
            return .groupable
        default:
            return isMCPReadOnly(toolName: name) ? .groupable : .standalone
        }
    }

    /// MCP tool names are shaped like `mcp__<server>__<tool>` in Claude's stream. Treat
    /// common read-only verb prefixes on the trailing `<tool>` segment as groupable; anything
    /// that looks like a create/update/delete/send call stays standalone.
    static func isMCPReadOnly(toolName: String) -> Bool {
        guard toolName.hasPrefix("mcp__"),
              let lastSeparator = toolName.range(of: "__", options: .backwards) else {
            return false
        }

        let suffix = String(toolName[lastSeparator.upperBound...]).lowercased()
        let readOnlyPrefixes = ["read", "list", "get", "search", "fetch", "describe", "query", "lookup", "show", "check"]
        return readOnlyPrefixes.contains { prefix in
            suffix == prefix
                || suffix.hasPrefix("\(prefix)_")
                || suffix.hasPrefix("\(prefix)-")
        }
    }
}
