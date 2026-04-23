import Foundation

enum ClaudeHookPolicy {
    static func shouldEnableHooks(permissionMode: String?) -> Bool {
        switch permissionMode {
        case "auto", "bypassPermissions", "dontAsk":
            return false
        default:
            return true
        }
    }

    static func shouldDefer(toolName: String, permissionMode: String?) -> Bool {
        switch permissionMode {
        case "auto", "bypassPermissions", "dontAsk":
            return false
        case "acceptEdits":
            return toolName == "Bash" || isMutatingMCPTool(toolName)
        default:
            return [
                "Bash",
                "Write",
                "Edit",
                "MultiEdit",
                "NotebookEdit"
            ].contains(toolName) || isMutatingMCPTool(toolName)
        }
    }

    private static func isMutatingMCPTool(_ toolName: String) -> Bool {
        guard toolName.hasPrefix("mcp__") else {
            return false
        }

        guard let lastComponent = toolName.split(separator: "__").last?.lowercased() else {
            return false
        }

        return [
            "write",
            "create",
            "update",
            "delete",
            "remove",
            "send",
            "post"
        ].contains { lastComponent.hasPrefix($0) }
    }
}
