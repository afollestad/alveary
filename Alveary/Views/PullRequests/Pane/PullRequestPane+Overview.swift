import AppKit
import SwiftUI

struct PullRequestPaneOverview: View, Equatable {
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel
    /// Switches the pane to the Changes tab; activity review threads link there.
    let onOpenFiles: () -> Void

    /// Everything rendered here comes from `session`, so a pane pass that carries the
    /// same one has nothing to redraw. `onOpenFiles` is excluded: it writes the pane's
    /// `@State` tab, whose storage outlives the struct copy the closure captured.
    nonisolated static func == (lhs: PullRequestPaneOverview, rhs: PullRequestPaneOverview) -> Bool {
        lhs.session == rhs.session && lhs.viewModel === rhs.viewModel
    }

    @State private var scrollPosition = ScrollPosition()
    /// Whether the reader is parked at the end of the timeline, which is what
    /// earns an appended entry an automatic scroll. Starts false so the first
    /// detail cannot scroll a freshly opened pane away from its header.
    @State private var isFollowingTimeline = false

    private var avatarLoader: GitHubAvatarLoader {
        viewModel.avatarLoader
    }

    /// The title's first-line height; the status icon and diff stats center inside
    /// this band so they stay aligned with line one even when the title wraps.
    private static let titleFirstLineHeight: CGFloat = {
        let titleFont = NSFont.systemFont(
            ofSize: NSFont.preferredFont(forTextStyle: .title3).pointSize,
            weight: .semibold
        )
        return titleFont.ascender - titleFont.descender + titleFont.leading
    }()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: PullRequestOverviewSectionMetrics.sectionSpacing) {
                // A pane opened from an identifier alone has no snapshot until its
                // first fetch backfills one, so the spinner or error banner below
                // stands in for the header. A loaded detail always has a summary
                // beside it, so this gate never hides a populated header.
                if let summary = session.summary {
                    headerSection(summary: summary)
                }

                if let error = session.detailError {
                    // No dismiss: without the detail the pane has nothing to show, so
                    // clearing the banner would leave an empty pane and no way back.
                    InlineBanner(
                        message: error,
                        severity: .error,
                        autoDismissAfter: nil,
                        actionTitle: "Retry",
                        onAction: { viewModel.retryDetailLoad() },
                        onDismiss: nil
                    )
                } else if session.isLoadingDetail, session.detail == nil {
                    StatusIndicatorSpinner(color: .secondary, diameter: 16, lineWidth: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityLabel("Loading pull request details")
                }

                if let detail = session.detail {
                    // The short metadata sections come first so review state stays
                    // above the fold whatever the description's length, leaving the
                    // description to run into the timeline it precedes.
                    //
                    // Local column reads, so this lands in the detail's first
                    // frame rather than reflowing the pane a second time.
                    PullRequestPaneLinkedOwners(identifier: detail.id)

                    if !detail.reviewers.isEmpty {
                        reviewersSection(detail.reviewers)
                    }

                    if !detail.checks.isEmpty {
                        PullRequestPaneChecks(checks: detail.checks)
                    }

                    descriptionSection(detail: detail)

                    // The conversation timeline follows the overview content.
                    if PullRequestPaneActivitySection.hasContent(
                        detail: detail,
                        proposedCommentCount: viewModel.pendingReviewProposal(for: .details(detail.id))?
                            .comments.count ?? 0
                    ) {
                        Divider()

                        PullRequestPaneActivitySection(
                            session: session,
                            detail: detail,
                            viewModel: viewModel,
                            onOpenFiles: onOpenFiles
                        )
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(ContextualPaneLayout.contentInsets())
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .modifier(TimelineBottomFollowing(
            itemCount: timelineItemCount,
            scrollPosition: $scrollPosition,
            isFollowing: $isFollowingTimeline
        ))
    }

    /// Everything the activity timeline can grow by. Closing, reopening, or
    /// marking ready appends a status event; replies and reviews land here too.
    private var timelineItemCount: Int {
        guard let detail = session.detail else {
            return 0
        }
        return detail.timelineEvents.count
            + detail.comments.count
            + detail.reviews.count
            + detail.reviewThreads.reduce(0) { $0 + $1.comments.count }
    }

    private func headerSection(summary: PullRequestSummary) -> some View {
        let title = session.detail?.title ?? summary.title
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                PullRequestStatusIcon(
                    status: session.detail?.status ?? summary.status,
                    isAccessibilityHidden: false
                )
                .frame(height: Self.titleFirstLineHeight)

                AppMarkdownInlineParagraph(text: title, textStyle: .title3, weight: .semibold)
                    .accessibilityLabel(
                        AppMarkdownInlineLabel.plainText(from: title, detectingFileMentions: false)
                    )
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                diffStats(summary: summary)
                    .frame(height: Self.titleFirstLineHeight)
            }

            metaRow(summary: summary)
        }
        // No trailing pad: the header sits on the pane's own content column with
        // the close and Open-on-GitHub glyphs above it, not on the timeline cards'
        // inset menu column. Its diff stats are text, so they right-align on that
        // column rather than taking the trailing glyph lane.
    }

    private func metaRow(summary: PullRequestSummary) -> some View {
        let authorLogin = session.detail?.authorLogin ?? summary.authorLogin
        let baseRefName = session.detail?.baseRefName ?? summary.baseRefName
        let headRefName = session.detail?.headRefName ?? summary.headRefName
        return HStack(spacing: 8) {
            HStack(spacing: 5) {
                PullRequestAvatarView(
                    login: authorLogin,
                    url: session.detail?.authorAvatarURL ?? summary.authorAvatarURL,
                    loader: avatarLoader
                )
                Text(authorLogin)
            }

            Text("\(baseRefName) \u{2190} \(headRefName)")
                .lineLimit(1)
                .truncationMode(.middle)

            // Holds the branch label off the trailing edge, so its middle
            // truncation kicks in before the text reaches the content column.
            Spacer(minLength: 8)
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private func diffStats(summary: PullRequestSummary) -> some View {
        HStack(spacing: 4) {
            Text("+\(session.detail?.additions ?? summary.additions)")
                .foregroundStyle(.green)
            Text("-\(session.detail?.deletions ?? summary.deletions)")
                .foregroundStyle(.red)
        }
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
    }

    /// GitHub's Reviewers sidebar, condensed: pending requests show a question
    /// mark, verdicts show their state icon, and past reviewers offer re-request.
    private func reviewersSection(_ reviewers: [PullRequestReviewer]) -> some View {
        PullRequestOverviewSection("Reviewers") {
            // Re-request failures land here, next to the button that caused them.
            // Outside the row stack, so the banner keeps the content column.
            if let error = session.reviewersError {
                InlineBanner(
                    message: error,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: { viewModel.clearReviewersError() }
                )
            }

            PullRequestOverviewSectionRows {
                ForEach(reviewers, id: \.login) { reviewer in
                    PullRequestPaneReviewerRow(
                        reviewer: reviewer,
                        avatarLoader: avatarLoader,
                        // One in-flight request per reviewer; the refetch then flips
                        // the row to "requested", which hides the button entirely.
                        isReRequestInFlight: session.reRequestsInFlight.contains(reviewer.login),
                        onReRequest: { viewModel.reRequestReview(from: reviewer.login) }
                    )
                }
            }
        }
    }

    /// The pull request body, last of the Overview's sections so it runs into the
    /// timeline beneath it. Its Edit menu rides the heading because the description
    /// has no author row of its own — edit only, since GitHub cannot delete one.
    private func descriptionSection(detail: PullRequestDetail) -> some View {
        PullRequestOverviewSection("Description") {
            if detail.viewerCanUpdate, !session.isEditingDescription {
                PullRequestCommentActionsMenu(
                    onEdit: { viewModel.openDescriptionEditor() },
                    onDelete: nil
                )
                // Off-card, so this one sits on the pane's trailing column and needs
                // the lane: its glyph centers in the hover circle rather than
                // trailing-aligning, so it no longer reaches the axis on its own.
                .contextualPaneTrailingGlyphLane(
                    controlWidth: PullRequestCommentActionsMenu.hitTargetSize.width
                )
            }
        } content: {
            description(detail: detail)
        }
    }

    @ViewBuilder
    private func description(detail: PullRequestDetail) -> some View {
        if session.isEditingDescription {
            // The description opens taller than a comment; everything else about
            // the editor — attachments included — is the shared comment chrome.
            PullRequestActivityCommentEditor(
                session: session,
                viewModel: viewModel,
                saveTitle: "Update description",
                placeholder: "Leave a description",
                minimumVisibleLineCount: 4
            )
        } else {
            renderedDescription(detail: detail)
        }
    }

    private func renderedDescription(detail: PullRequestDetail) -> some View {
        let body = PullRequestMarkdown.sanitized(detail.bodyMarkdown)
        return VStack(alignment: .leading, spacing: 8) {
            if body.isEmpty {
                Text("No description.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            } else {
                AppMarkdownText(markdown: body)
                    .environment(\.openURL, OpenURLAction { url in
                        UIApplicationShim.open(url: url)
                        return .handled
                    })
            }

            // The PR body is reactable like any comment; reactions target the
            // pull request's own node id.
            if let nodeID = detail.nodeID {
                CommentReactionBar(
                    reactions: detail.reactions.map(\.asCommentReaction),
                    options: PullRequestReactionContent.pickerOptions,
                    onToggle: { content in
                        viewModel.toggleReaction(
                            subjectID: nodeID,
                            content: content,
                            viewerHasReacted: detail.reactions.first { $0.content.rawValue == content }?
                                .viewerHasReacted ?? false
                        )
                    }
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

}

struct PullRequestPaneChecks: View {
    let checks: [PullRequestCheck]

    var body: some View {
        PullRequestOverviewSection("Checks") {
            PullRequestOverviewSectionRows {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                    PullRequestCheckRow(check: check)
                }
            }
        }
    }
}

/// One reviewer. Extracted so the Reviewers section stays a short expression —
/// see the type-check budget rules in `Alveary/Views/AGENTS.md`.
private struct PullRequestPaneReviewerRow: View {
    let reviewer: PullRequestReviewer
    let avatarLoader: GitHubAvatarLoader
    let isReRequestInFlight: Bool
    let onReRequest: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 6) {
            PullRequestAvatarView(login: reviewer.login, url: reviewer.avatarURL, loader: avatarLoader)

            Text(reviewer.login)
                .font(.callout)

            if reviewer.isBot {
                PullRequestBotBadge()
            }

            Spacer(minLength: 8)

            if reviewer.canReRequest {
                Button(action: onReRequest) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .semibold))
                }
                // The tint rides the style's parameter, not a local
                // `foregroundStyle`, so it still fades through hover and disabled.
                .iconActionButtonStyle(.inline, foregroundColor: .secondary)
                .disabled(isReRequestInFlight)
                .help("Re-request review from \(reviewer.login)")
                .accessibilityLabel("Re-request review from \(reviewer.login)")
            }

            // On the lane here rather than inside `stateIcon`, so the four verdict
            // glyphs — which differ in ink width — share one axis without each
            // case restating it.
            stateIcon
                .contextualPaneTrailingGlyphLane()
        }
        .pullRequestOverviewRowInsets()
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var stateIcon: some View {
        switch reviewer.state {
        case .requested:
            Image(systemName: "questionmark.circle")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Review requested")
        case .approved:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.green)
                .accessibilityLabel("Approved")
        case .changesRequested:
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
                .accessibilityLabel("Requested changes")
        case .commented:
            Image(systemName: "bubble.left")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Commented")
        }
    }
}

private struct PullRequestCheckRow: View {
    let check: PullRequestCheck

    var body: some View {
        if let detailsURL = check.detailsURL {
            // One hit target for the whole row; the trailing arrow is decorative.
            Button {
                UIApplicationShim.open(url: detailsURL)
            } label: {
                rowContent(showsLinkGlyph: true)
            }
            .buttonStyle(PullRequestPaneRowButtonStyle())
            .accessibilityLabel("\(check.name), \(stateAccessibilityName)")
            .accessibilityHint("Opens the check's details page")
        } else {
            rowContent(showsLinkGlyph: false)
                .pullRequestOverviewRowInsets()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(check.name), \(stateAccessibilityName)")
        }
    }

    private func rowContent(showsLinkGlyph: Bool) -> some View {
        HStack(spacing: 8) {
            indicator
                .frame(width: 12, alignment: .center)

            Text(check.name)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if showsLinkGlyph {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .contextualPaneTrailingGlyphLane()
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var indicator: some View {
        switch check.state {
        case .passing:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        case .failing:
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.red)
        case .pending:
            StatusIndicatorSpinner(color: .secondary)
        }
    }

    private var stateAccessibilityName: String {
        switch check.state {
        case .passing:
            return "passing"
        case .failing:
            return "failing"
        case .pending:
            return "in progress"
        }
    }
}
