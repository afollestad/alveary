import Foundation

/// Keep preview and fallback counts consistent with the comments confirmation would publish.
extension AppKitReviewProposalWidgetView {
    /// One total first, with the pending share broken out only when both sources are present.
    static func loadedCommentSummary(_ preview: PullRequestReviewProposalPreview) -> String {
        let total = preview.proposedCommentCount + preview.pendingCommentCount
        guard total > 0 else {
            return "Publishes the review summary only — no inline comments are staged or pending."
        }
        var summary = "Publishes \(total) review comment\(total == 1 ? "" : "s")"
        if preview.proposedCommentCount > 0, preview.pendingCommentCount > 0 {
            summary += ", including \(preview.pendingCommentCount) already-pending draft comment" +
                "\(preview.pendingCommentCount == 1 ? "" : "s")"
        }
        summary += "."
        if preview.hiddenFileCount > 0 {
            summary += " \(preview.hiddenFileCount) more file" +
                "\(preview.hiddenFileCount == 1 ? "" : "s") not shown; open the pull request to read them all."
        }
        return summary
    }

    /// Without a loaded preview the counts come from the presentation, then the call snapshot.
    static func fallbackCommentTotal(_ configuration: Configuration) -> Int {
        if let presentation = configuration.presentation {
            return presentation.comments.count + presentation.pendingCommentCount
        }
        return (configuration.content.commentCount ?? 0) + (configuration.content.pendingCommentCount ?? 0)
    }
}
