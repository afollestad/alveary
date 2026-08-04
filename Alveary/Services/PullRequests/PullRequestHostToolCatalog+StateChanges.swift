import AgentCLIKit
import Foundation

/// The tools that change the pull request's own state: close, reopen, and both draft directions.
/// Each names the tool that undoes it, so the model never describes one as final.
extension PullRequestHostToolCatalog {
    static let closeTool = AgentCLIKit.AgentHostToolDefinition(
        name: closeToolName,
        title: "Close a pull request",
        description: """
        Close an open or draft pull request on GitHub without merging it. Applies immediately, after the user explicitly \
        asks to close it; reopen_pr undoes it while the head branch still exists, and merging is not something these tools \
        can do. Requires write access, and is the one pull request tool refused to automated scheduled runs. Closing an \
        already-closed pull request reports already_closed and changes nothing; a merged one cannot be closed.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["url": HostToolSchema.nonEmptyStringSchema],
            required: ["url"]
        ),
        outputSchema: stateChangeOutputSchema(["closed", "already_closed", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let reopenTool = AgentCLIKit.AgentHostToolDefinition(
        name: reopenToolName,
        title: "Reopen a closed pull request",
        description: """
        Reopen a pull request that was closed on GitHub, named by its url. This is not how a pull request gets opened in \
        the first place: it revives one that already exists, so "open a pull request" for work that has none is never this \
        tool. Applies immediately, after the user explicitly asks for it. Requires write access. A merged pull request can \
        never be reopened, and GitHub refuses once the head branch has been deleted — the refusal names the missing \
        branch. Reopening an already-open pull request reports already_open and changes nothing.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["url": HostToolSchema.nonEmptyStringSchema],
            required: ["url"]
        ),
        outputSchema: stateChangeOutputSchema(["reopened", "already_open", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let markReadyTool = AgentCLIKit.AgentHostToolDefinition(
        name: markReadyToolName,
        title: "Mark a draft pull request ready for review",
        description: """
        Take a draft pull request out of draft on GitHub, so reviewers are notified. Applies immediately; mark_pr_draft \
        undoes it. Requires write access. One that is not a draft reports already_ready and changes nothing; a closed or \
        merged one cannot be marked ready.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["url": HostToolSchema.nonEmptyStringSchema],
            required: ["url"]
        ),
        outputSchema: stateChangeOutputSchema(["marked_ready", "already_ready", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )

    static let markDraftTool = AgentCLIKit.AgentHostToolDefinition(
        name: markDraftToolName,
        title: "Return an open pull request to draft",
        description: """
        Put an open pull request back into draft on GitHub. Applies immediately; mark_pr_ready undoes it. Requires write \
        access. One that is already a draft reports already_draft and changes nothing; a closed or merged one cannot be \
        returned to draft.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["url": HostToolSchema.nonEmptyStringSchema],
            required: ["url"]
        ),
        outputSchema: stateChangeOutputSchema(["marked_draft", "already_draft", "error"]),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )
}
