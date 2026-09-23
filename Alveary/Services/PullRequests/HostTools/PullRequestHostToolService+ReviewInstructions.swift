import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Launched single-agent tasks retain their workflow; ordinary requests follow current settings.
    func pullRequestReviewInstructions(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        let source = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        // A launched task's saved instructions name a pull request its launch already fetched, so
        // reading it again would only spend the user's shared GitHub quota.
        let instructions: String
        if let saved = try PullRequestReviewLaunchInstructions.instructions(for: identifier, in: source.conversation) {
            instructions = saved
        } else {
            // Fetched rather than assumed: the title goes into the instructions, and a URL naming a
            // pull request that does not exist should fail here rather than halfway through a review.
            let pullRequest = try await fetchReviewContext(identifier)
            instructions = PullRequestReviewPromptBuilder.reviewInstructions(
                settings: settingsService.current,
                url: pullRequest.url ?? Self.fallbackURL(for: identifier),
                identifier: identifier,
                title: pullRequest.title
            )
        }

        return AgentCLIKit.AgentHostToolResult(
            text: instructions,
            structuredContent: .object([
                "repository": .string(identifier.nameWithOwner),
                "number": .number(Double(identifier.number)),
                "instructions": .string(instructions)
            ])
        )
    }

    /// `PullRequestDetail.url` is optional; the identifier always reconstructs the canonical one.
    static func fallbackURL(for identifier: PullRequestIdentifier) -> URL {
        URL(string: "https://github.com/\(identifier.nameWithOwner)/pull/\(identifier.number)")
            ?? URL(fileURLWithPath: "/")
    }
}
