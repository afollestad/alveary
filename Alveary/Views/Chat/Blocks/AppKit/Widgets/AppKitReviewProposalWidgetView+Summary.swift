import Foundation

/// Keep preview and fallback counts consistent with the comments confirmation would publish.
extension AppKitReviewProposalWidgetView {
    static let noInlineCommentsSummary = "No inline comments are staged or pending."

    /// One total first, with the pending share broken out only when both sources are present.
    static func loadedCommentSummary(_ preview: PullRequestReviewProposalPreview) -> String {
        let total = preview.proposedCommentCount + preview.pendingCommentCount
        guard total > 0 else {
            return noInlineCommentsSummary
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

/// Shared verdict names and sizing for the proposal card.
extension AppKitReviewProposalWidgetView {
    static let selectableEvents: [PullRequestReviewEvent] = [.approve, .requestChanges, .comment]
    /// Past this the card is sized by one long code line rather than by its controls.
    static let maximumDiffWidth: CGFloat = 560
    /// Clearance between the diff preview and the action row, replacing the stack's ordinary spacing.
    static let actionRowSeparation: CGFloat = 12

    static func verdictLabel(_ event: PullRequestReviewEvent) -> String {
        switch event {
        case .approve:
            "Approve"
        case .requestChanges:
            "Request changes"
        case .comment:
            "Comment"
        }
    }

    /// Leading glyph naming the verdict the primary half would submit. Matches
    /// the pull-request pane's review footer so a verdict reads the same on
    /// both surfaces.
    static func verdictIcon(_ event: PullRequestReviewEvent) -> ActionIcon {
        switch event {
        case .approve:
            .octicon(.checkCircle16)
        case .requestChanges:
            .octicon(.alert16)
        case .comment:
            .octicon(.codeReview16)
        }
    }

}

/// Restrict updates to the card sections whose render inputs changed.
extension AppKitReviewProposalWidgetView {
    /// Summary changes must not unmount the editor or reconfigure unchanged diff cards.
    static func needsBodyRebuild(_ old: Configuration?, _ new: Configuration) -> Bool {
        guard let old else { return true }
        return old.content != new.content || old.presentation?.id != new.presentation?.id
            || old.preview != new.preview || old.isInteractive != new.isInteractive || old.isSubmitting != new.isSubmitting
            || old.selectedEvent != new.selectedEvent || old.errorMessage != new.errorMessage || old.outcome != new.outcome
            || old.typography != new.typography || old.presentation?.comments != new.presentation?.comments
            || old.presentation?.reviewers != new.presentation?.reviewers
            || old.presentation?.collectiveCompletionWarning != new.presentation?.collectiveCompletionWarning
            || old.presentation?.pendingCommentCount != new.presentation?.pendingCommentCount
            || old.summaryBody.isEmpty != new.summaryBody.isEmpty
    }

}
