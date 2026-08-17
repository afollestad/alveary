import AgentCLIKit
import Foundation

/// `get_pr_review_proposal`'s definition. `internal` rather than `private` so the `tools` array in
/// the main catalog file can still reach it.
extension PullRequestHostToolCatalog {
    /// What is already staged for a pull request, so a second review adds to it instead of
    /// replacing it blind.
    ///
    /// A proposal lives on the conversation that opened it, and an agentic review runs in a new
    /// thread — so without this the model cannot see the comments its own `propose_pr_review` is
    /// about to supersede.
    static let reviewProposalTool = AgentCLIKit.AgentHostToolDefinition(
        name: reviewProposalToolName,
        title: "Get a pull request's unconfirmed review proposal",
        description: """
        Read the review proposal already waiting for the user's confirmation on a pull request, if there is one: its \
        verdict, summary, and every inline comment staged for it. These are staged inside Alveary and exist nowhere on \
        GitHub — get_pr and get_pr_diff report the user's own GitHub-side pending draft, which is a different thing. \
        Call this before propose_pr_review whenever you may be reviewing a pull request a second time: a new proposal \
        replaces the pending one entirely, and a staged comment you do not pass back is deleted — carry them all \
        forward alongside your new ones, and never treat them as feedback already given. \
        Returns has_proposal false when nothing is pending. Reads only; it confirms nothing and notifies no one.
        """,
        inputSchema: HostToolSchema.strictObject(
            properties: ["url": HostToolSchema.nonEmptyStringSchema],
            required: ["url"]
        ),
        outputSchema: HostToolSchema.strictObject(
            properties: [
                "repository": HostToolSchema.stringSchema,
                "number": HostToolSchema.integerSchema(minimum: 1),
                "has_proposal": HostToolSchema.booleanSchema,
                "event": HostToolSchema.stringSchema,
                "body": HostToolSchema.stringSchema,
                // The same shape `propose_pr_review` accepts, so carrying a comment forward is a
                // copy rather than a translation.
                "comments": HostToolSchema.arraySchema(items: reviewCommentInputSchema)
            ],
            required: ["repository", "number", "has_proposal"]
        ),
        annotations: HostToolSchema.readOnlyAnnotations
    )
}
