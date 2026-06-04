import AgentCLIKit
import Foundation

/// UI-facing approval policy for Claude tool rows rendered by Alveary.
///
/// Provider-level hook matching and defer decisions live in `AgentCLIKit.ClaudeHookPolicy`.
/// This type only adds Alveary display rules, such as hiding `AskUserQuestion` from the
/// generic tool-approval UI and batching rows that belong to the same visible tool family.
enum ClaudeApprovalDisplayPolicy {
    /// Returns whether Alveary should render a generic tool-approval prompt for a Claude tool.
    static func canRenderToolApproval(_ toolName: String) -> Bool {
        toolName != "AskUserQuestion" &&
            AgentCLIKit.ClaudeHookPolicy.isPotentiallyApprovalControlledTool(toolName)
    }

    /// Returns whether an observed tool call can join the current approval batch.
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

    /// Returns whether a deferred tool event should join the current approval batch.
    static func shouldBatchDeferredToolCall(
        toolName: String,
        with approvalToolNames: [String],
        permissionMode: String?
    ) -> Bool {
        guard AgentCLIKit.ClaudeHookPolicy.shouldDefer(toolName: toolName, permissionMode: permissionMode) else {
            return false
        }
        return canBatchPotentialApprovalToolCall(
            toolName: toolName,
            with: approvalToolNames
        )
    }
}
