import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// Launched single-agent tasks retain their workflow; ordinary requests follow current settings.
    func pullRequestReviewInstructions(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        // Fetched rather than assumed: the title goes into the instructions, and a URL naming a
        // pull request that does not exist should fail here rather than halfway through a review.
        let detail = try await fetchDetail(identifier)
        let source = try resolveSource(context: context)
        let instructions = try PullRequestReviewLaunchInstructions.instructions(for: identifier, in: source.conversation)
            ?? PullRequestReviewPromptBuilder.reviewInstructions(
                settings: settingsService.current,
                url: detail.url ?? Self.fallbackURL(for: identifier),
                identifier: identifier,
                title: detail.title
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

    /// `PullRequestDetail.url` is optional; the identifier always reconstructs the canonical one.
    static func fallbackURL(for identifier: PullRequestIdentifier) -> URL {
        URL(string: "https://github.com/\(identifier.nameWithOwner)/pull/\(identifier.number)")
            ?? URL(fileURLWithPath: "/")
    }
}
