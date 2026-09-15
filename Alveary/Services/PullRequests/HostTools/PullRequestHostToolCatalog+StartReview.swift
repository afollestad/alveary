import AgentCLIKit
import Foundation

extension PullRequestHostToolCatalog {
    static let startReviewTool = AgentCLIKit.AgentHostToolDefinition(
        name: startReviewToolName,
        title: "Start a pull request review task",
        description: """
        Launch a dedicated review task using the user's saved review mode, agents, criteria, and sidebar section. \
        Call when get_pr_review_instructions directs you here, or when asked to launch review tasks. Links the PR \
        automatically. Returns an existing unfinished review instead of duplicating it. The returned thread_id identifies \
        the Alveary task. Report the returned status and \
        leave the review to that task; completion and any required user action appear there. Starts immediately, but \
        submits nothing to GitHub. For a review in this conversation, read get_pr_review_instructions first.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["url": HostToolSchema.nonEmptyStringSchema],
            required: ["url"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "status": HostToolSchema.enumSchema(["started", "existing", "error"]),
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "thread_id": HostToolSchema.stringSchema,
                "name": HostToolSchema.stringSchema,
                "review_mode": HostToolSchema.enumSchema(["singleAgent", "reviewTeam"]),
                "run_id": HostToolSchema.stringSchema,
                "phase": HostToolSchema.stringSchema,
                "link_warning": HostToolSchema.stringSchema,
                "message": HostToolSchema.stringSchema
            ],
            required: ["status", "message"]
        ),
        annotations: HostToolSchema.reversibleMutationAnnotations
    )
}
