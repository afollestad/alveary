import AgentCLIKit
import Foundation

extension PullRequestHostToolService {
    /// The user's review guidance, fetched at the start of every review — by a thread the
    /// footer's "Agentic review" button spawned and by one the user asked directly, so the two
    /// routes cannot drift.
    ///
    /// The model calling this is how Alveary learns a review was asked for. Deciding that from
    /// the wording of a message would need intent heuristics — and "I already reviewed #42" reads
    /// the same to a regex as "review #42" — so the decision stays with the model, which
    /// understands the sentence. A call made in error costs a read and nothing else.
    func pullRequestReviewInstructions(
        context: AgentCLIKit.AgentHostToolCallContext,
        arguments: [String: AgentCLIKit.JSONValue]
    ) async throws -> AgentCLIKit.AgentHostToolResult {
        _ = try resolveSource(context: context)
        let identifier = try parseIdentifier(arguments: arguments)
        // Fetched rather than assumed: the title goes into the instructions, and a URL naming a
        // pull request that does not exist should fail here rather than halfway through a review.
        let detail = try await fetchDetail(identifier)
        let instructions = PullRequestReviewPromptBuilder.reviewInstructions(
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
