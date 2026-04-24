import Foundation

enum ClaudeHookPolicy {
    private static let directlyApprovalControlledTools = [
        "Bash",
        "Write",
        "Edit",
        "MultiEdit",
        "NotebookEdit"
    ]
    private static let observedLifecycleTools = [
        "EnterPlanMode",
        "ExitPlanMode"
    ]

    static var preToolUseMatcher: String {
        (["AskUserQuestion"] + directlyApprovalControlledTools + observedLifecycleTools + ["mcp__.*"])
            .joined(separator: "|")
    }

    static func shouldEnableHooks(permissionMode: String?) -> Bool {
        switch permissionMode {
        case "auto", "bypassPermissions", "dontAsk":
            return false
        default:
            return true
        }
    }

    static func shouldDefer(toolName: String, permissionMode: String?) -> Bool {
        if toolName == "AskUserQuestion" {
            return true
        }

        if toolName == "ExitPlanMode" {
            return permissionMode == "plan"
        }

        switch permissionMode {
        case "auto", "bypassPermissions", "dontAsk":
            return false
        case "acceptEdits":
            return toolName == "Bash" || isMutatingMCPTool(toolName)
        default:
            return isPotentiallyApprovalControlledTool(toolName)
        }
    }

    static func isPotentiallyApprovalControlledTool(_ toolName: String) -> Bool {
        switch toolName {
        case "AskUserQuestion", "ExitPlanMode":
            return true
        default:
            return directlyApprovalControlledTools.contains(toolName) || isMutatingMCPTool(toolName)
        }
    }

    static func canRenderToolApproval(_ toolName: String) -> Bool {
        toolName != "AskUserQuestion" && isPotentiallyApprovalControlledTool(toolName)
    }

    static func canBatchPotentialApprovalToolCall(
        toolName: String,
        with approvalToolNames: [String]
    ) -> Bool {
        guard canRenderToolApproval(toolName),
              !approvalToolNames.isEmpty else {
            return false
        }
        return approvalToolNames.allSatisfy { $0 == toolName }
    }

    static func shouldBatchDeferredToolCall(
        toolName: String,
        with approvalToolNames: [String],
        permissionMode: String?
    ) -> Bool {
        guard shouldDefer(toolName: toolName, permissionMode: permissionMode) else {
            return false
        }
        return canBatchPotentialApprovalToolCall(
            toolName: toolName,
            with: approvalToolNames
        )
    }

    static func isMutatingMCPTool(_ toolName: String) -> Bool {
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
