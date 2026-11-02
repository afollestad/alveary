import AppKit

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

    /// Only failures the card itself produced. A refused call's reason is *not* here: the shell
    /// already gives it the detail line, which `HostToolWidgetSummary.detail(for:)` hands the
    /// message on `.failed`, and repeating it as a banner printed the same sentence twice.
    ///
    /// `AppKitScheduledTaskProposalWidgetView.bannerMessages` still appends its own, and must:
    /// its detail line carries the schedule summary rather than the message, so the banner is the
    /// only place a refusal reaches that card. Do not unify the two.
    static func bannerMessages(_ configuration: Configuration) -> [String] {
        var messages: [String] = []
        if configuration.isInteractive, configuration.summaryBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let event = configuration.selectedEvent ?? configuration.content.event
            if event == .requestChanges {
                messages.append("Request changes requires a top-level comment.")
            } else if event == .comment, fallbackCommentTotal(configuration) == 0 {
                messages.append("Add a top-level comment or a review thread to submit a comment review.")
            }
        }
        if configuration.isInteractive, let errorMessage = configuration.errorMessage {
            messages.append(errorMessage)
        }
        if case .failed(let message) = configuration.preview, configuration.isInteractive {
            messages.append("Could not load the review's comments: \(message)")
        }
        return messages
    }

    static func bannerLabels(_ configuration: Configuration) -> [NSView] {
        bannerMessages(configuration).map { message in
            AppKitTranscriptWidgetLabelFactory.label(
                message, level: .caption, color: .systemRed, typography: configuration.typography, wraps: true
            )
        }
    }
}

/// Shared verdict names and sizing for the proposal card.
extension AppKitReviewProposalWidgetView {
    static let selectableEvents: [PullRequestReviewEvent] = [.approve, .requestChanges, .comment]
    /// Past this the card is sized by one long code line rather than by its controls.
    static let maximumDiffWidth: CGFloat = 560
    /// Clearance between the card's body (the diff preview, or the published comments) and its footer
    /// (the top-level comment, then the controls), replacing the stack's ordinary spacing.
    static let footerSeparation: CGFloat = 12
    /// Clearance around the rule between the top-level comment and the controls; at the stack's
    /// ordinary spacing the two groups crowd it and read as one. Less above than below because a
    /// pending comment ends in inline actions whose 24pt hit target already leaves ~7pt blank under
    /// the text, so equal gaps read as lopsided.
    static let footerDividerSpacingAbove: CGFloat = 10
    static let footerDividerSpacingBelow: CGFloat = 16

    static func button(
        title: String,
        icon: ActionIcon,
        style: AppKitTranscriptApprovalButtonStyle,
        target: AnyObject,
        action: Selector
    ) -> AppKitTranscriptApprovalButton {
        let button = AppKitTranscriptApprovalButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.title = title
        button.icon = icon
        button.actionStyle = style
        button.target = target
        button.action = action
        return button
    }

    static func buttonRow(_ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        return row
    }

    /// The submitted review's own record first: a submitted card may have no presentation, and its
    /// call snapshot's identifier is optional.
    static func pullRequestIdentifier(_ configuration: Configuration) -> PullRequestIdentifier? {
        configuration.published?.review.identifier ?? configuration.presentation?.identifier ?? configuration.content.identifier
    }

    /// GitHub rejects approving or requesting changes on your own pull request, so the card refuses
    /// them rather than letting a confirmation fail at submission.
    static func isSelfReviewVerdict(_ event: PullRequestReviewEvent, _ configuration: Configuration) -> Bool {
        let viewerIsAuthor = configuration.preview?.loadedPreview?.viewerIsAuthor ?? false
        return viewerIsAuthor && (event == .approve || event == .requestChanges)
    }

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
            || old.summaryBody.isEmpty != new.summaryBody.isEmpty || old.published != new.published
    }
}

extension PullRequestReviewProposalPreviewState {
    var loadedPreview: PullRequestReviewProposalPreview? {
        guard case .loaded(let preview) = self else {
            return nil
        }
        return preview
    }
}

extension Optional where Wrapped == PullRequestReviewProposalPreviewState {
    var loadedPreview: PullRequestReviewProposalPreview? {
        self?.loadedPreview
    }
}
