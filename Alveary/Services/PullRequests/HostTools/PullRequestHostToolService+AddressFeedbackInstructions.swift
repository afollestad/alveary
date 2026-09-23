import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// The user's guidance for addressing a pull request's feedback, fetched at the start of
    /// every such run — by a thread the footer's "Address feedback" button spawned and by one
    /// the user asked directly, so the two routes cannot drift.
    ///
    /// The review sibling's rules apply unchanged: the model calling this is how Alveary learns
    /// feedback is about to be addressed, and the pull request is fetched rather than assumed so
    /// a bad URL fails here instead of halfway through a run the model has begun narrating.
    func pullRequestAddressFeedbackInstructions(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        let pullRequest = try await fetchReviewContext(identifier)
        let instructions = PullRequestReviewPromptBuilder.addressFeedbackInstructions(
            settings: settingsService.current,
            url: pullRequest.url ?? Self.fallbackURL(for: identifier),
            identifier: identifier,
            title: pullRequest.title
        )

        return AgentCLIKit.AgentHostToolResult(
            text: instructions,
            structuredContent: .object([
                "repository": .string(identifier.nameWithOwner),
                "number": .number(Double(identifier.number)),
                "instructions": .string(instructions)
            ])
        )
    }
}
