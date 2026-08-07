import Foundation

/// Composes what `get_pr_review_instructions` returns: the user's editable instructions
/// followed by a fixed block naming the pull request. The context block is what keeps a
/// fully rewritten prompt pointed at a target, so it is never part of the editable half.
enum PullRequestReviewPromptBuilder {
    /// The one composition every review follows. Both routes fetch it through the tool —
    /// a thread the footer's "Agentic review" spawned and a thread the user asked directly
    /// — so the guidance cannot drift between them.
    static func reviewInstructions(
        settings: AppSettings,
        url: URL,
        identifier: PullRequestIdentifier,
        title: String?
    ) -> String {
        build(
            editablePrompt: settings.pullRequestReviewPrompt,
            context: context(url: url, identifier: identifier, title: title)
        )
    }

    static func build(editablePrompt: String, context: String) -> String {
        [
            editablePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            context.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    static func context(url: URL, identifier: PullRequestIdentifier, title: String?) -> String {
        var rows = ["- Pull request: `\(identifier.displayKey)`"]
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            rows.append("- Title: \(title)")
        }
        rows.append("- URL: \(url.absoluteString)")
        return """
        ## Pull request
        \(rows.joined(separator: "\n"))
        """
    }
}
