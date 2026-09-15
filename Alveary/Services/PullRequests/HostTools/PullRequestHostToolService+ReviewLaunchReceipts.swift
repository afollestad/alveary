import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    func reviewLaunchRecordedResult(_ receipt: PullRequestHostToolReceipt) -> AgentCLIKit.AgentHostToolResult {
        AgentCLIKit.AgentHostToolResult(
            text: receipt.message, structuredContent: receipt.reviewLaunchResult, isError: receipt.reviewLaunchIsError ?? false
        )
    }

    /// A failed final save leaves the earlier destination receipt intact as a retry barrier.
    func storeReviewLaunchFailure(
        _ result: AgentCLIKit.AgentHostToolResult,
        identity: PullRequestHostToolCallIdentity,
        context: AgentCLIKit.AgentHostToolCallContext
    ) {
        do {
            try storeReviewLaunchResult(result, identity: identity, context: context)
        } catch {
            retainReviewLaunchFailure(result, identity: identity)
        }
    }

    /// Failed disk writes must still prevent a live provider's exact retry from creating another task.
    func retainReviewLaunchFailure(_ result: AgentCLIKit.AgentHostToolResult, identity: PullRequestHostToolCallIdentity) {
        var receipt = makeReceipt(
            identity: identity, toolName: PullRequestHostToolCatalog.startReviewToolName, status: "error", message: result.text
        )
        receipt.reviewLaunchResult = result.structuredContent
        receipt.reviewLaunchIsError = true
        reviewLaunchFallbackReceipts[identity.deduplicationKey] = receipt
        if reviewLaunchFallbackReceipts.count > HostToolReceiptLedger.maximumReceiptCount,
           let oldest = reviewLaunchFallbackReceipts.values.min(by: { $0.createdAt < $1.createdAt }) {
            reviewLaunchFallbackReceipts.removeValue(forKey: oldest.deduplicationKey)
        }
    }

    /// Saves separately from task insertion so a failed checkpoint cannot roll back a task already visible in the sidebar.
    func storeReviewLaunchResult(
        _ result: AgentCLIKit.AgentHostToolResult,
        identity: PullRequestHostToolCallIdentity,
        context: AgentCLIKit.AgentHostToolCallContext
    ) throws {
        try flushPendingChanges()
        let source = try resolveSource(context: context)
        guard case .object(let content) = result.structuredContent, case .string(let status) = content["status"] else {
            throw PullRequestHostToolServiceError.persistenceFailure
        }
        var receipt = makeReceipt(
            identity: identity, toolName: PullRequestHostToolCatalog.startReviewToolName, status: status, message: result.text
        )
        receipt.reviewLaunchResult = result.structuredContent
        receipt.reviewLaunchIsError = result.isError
        do {
            try source.conversation.updatePullRequestReviewLaunchReceipt(receipt)
            try reviewReceiptSave(modelContext)
        } catch {
            modelContext.rollback()
            throw PullRequestHostToolServiceError.persistenceFailure
        }
    }
}
