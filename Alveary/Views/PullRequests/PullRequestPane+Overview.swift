import AppKit
import SwiftUI

struct PullRequestPaneOverview: View {
    let session: PullRequestPaneSession
    let viewModel: PullRequestsViewModel
    /// Switches the pane to the Changes tab; activity review threads link there.
    let onOpenFiles: () -> Void

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
            VStack(alignment: .leading, spacing: 16) {
                headerSection

                if let error = session.detailError {
                    InlineBanner(message: error, severity: .error, autoDismissAfter: nil, onDismiss: nil)
                } else if session.isLoadingDetail, session.detail == nil {
                    StatusIndicatorSpinner(color: .secondary, diameter: 16, lineWidth: 2)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .accessibilityLabel("Loading pull request details")
                }

                if let detail = session.detail {
                    // The description follows the author/branch header directly —
                    // no divider between them — with Reviewers and Checks below it.
                    description(detail: detail)

                    if !detail.reviewers.isEmpty {
                        reviewersSection(detail.reviewers)
                    }

                    if !detail.checks.isEmpty {
                        PullRequestPaneChecks(checks: detail.checks)
                    }

                    // The conversation timeline follows the overview content.
                    if PullRequestPaneActivitySection.hasContent(detail: detail) {
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

    private var headerSection: some View {
        // The header's trailing column (diff stats, the description Edit menu)
        // aligns to the timeline cards' menu column below: 16pt content inset
        // plus this pad equals the clearance an interactive control needs to
        // stay out of the scroll indicator's grab region.
        let trailingLanePad = AppScrollIndicatorLayout.interactiveTrailingClearance
            - ContextualPaneLayout.horizontalInset
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                PullRequestStatusIcon(
                    status: session.detail?.status ?? session.summary.status,
                    isAccessibilityHidden: false
                )
                .frame(height: Self.titleFirstLineHeight)

                Text(session.detail?.title ?? session.summary.title)
                    .font(.title3.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Spacer(minLength: 8)

                diffStats
                    .frame(height: Self.titleFirstLineHeight)
            }

            metaRow
        }
        .padding(.trailing, trailingLanePad)
    }

    private var metaRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 5) {
                PullRequestAvatarView(
                    login: authorLogin,
                    url: session.detail?.authorAvatarURL ?? session.summary.authorAvatarURL,
                    loader: avatarLoader
                )
                Text(authorLogin)
            }

            Text("\(baseRefName) \u{2190} \(headRefName)")
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 8)

            // The description has no author row of its own, so its Edit menu
            // rides the meta line. Edit only: a description cannot be deleted.
            if session.detail?.viewerCanUpdate == true, !session.isEditingDescription {
                PullRequestCommentActionsMenu(
                    onEdit: { viewModel.openDescriptionEditor() },
                    onDelete: nil
                )
            }
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
    }

    private var diffStats: some View {
        HStack(spacing: 4) {
            Text("+\(session.detail?.additions ?? session.summary.additions)")
                .foregroundStyle(.green)
            Text("-\(session.detail?.deletions ?? session.summary.deletions)")
                .foregroundStyle(.red)
        }
        .font(.subheadline.weight(.medium))
        .monospacedDigit()
    }

    /// GitHub's Reviewers sidebar, condensed: pending requests show a question
    /// mark, verdicts show their state icon, and past reviewers offer re-request.
    private func reviewersSection(_ reviewers: [PullRequestReviewer]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Reviewers")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.tertiary)
                .accessibilityAddTraits(.isHeader)

            // Re-request failures land here, next to the button that caused them.
            if let error = session.reviewersError {
                InlineBanner(
                    message: error,
                    severity: .error,
                    autoDismissAfter: nil,
                    onDismiss: { viewModel.clearReviewersError() }
                )
            }

            ForEach(reviewers, id: \.login) { reviewer in
                HStack(alignment: .center, spacing: 6) {
                    PullRequestAvatarView(login: reviewer.login, url: reviewer.avatarURL, loader: avatarLoader)

                    Text(reviewer.login)
                        .font(.callout)

                    if reviewer.isBot {
                        PullRequestBotBadge()
                    }

                    Spacer(minLength: 8)

                    if reviewer.canReRequest {
                        Button {
                            viewModel.reRequestReview(from: reviewer.login)
                        } label: {
                            Image(systemName: "arrow.clockwise")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(.secondary)
                                .frame(width: 22, height: 20)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // One in-flight request per reviewer; the refetch then flips
                        // the row to "requested", which hides the button entirely.
                        .disabled(session.reRequestsInFlight.contains(reviewer.login))
                        .help("Re-request review from \(reviewer.login)")
                        .accessibilityLabel("Re-request review from \(reviewer.login)")
                    }

                    reviewerStateIcon(reviewer.state)
                }
                .accessibilityElement(children: .combine)
            }
        }
    }

    @ViewBuilder
    private func reviewerStateIcon(_ state: PullRequestReviewer.State) -> some View {
        switch state {
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

    private var authorLogin: String {
        session.detail?.authorLogin ?? session.summary.authorLogin
    }

    private var baseRefName: String {
        session.detail?.baseRefName ?? session.summary.baseRefName
    }

    private var headRefName: String {
        session.detail?.headRefName ?? session.summary.headRefName
    }

}

struct PullRequestPaneChecks: View {
    let checks: [PullRequestCheck]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Checks")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(checks.enumerated()), id: \.offset) { _, check in
                    PullRequestCheckRow(check: check)
                }
            }
            // Row hover/press fills carry their own 8pt inset; pull the stack back so
            // row text stays aligned with the section heading.
            .padding(.horizontal, -8)
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
            .buttonStyle(PullRequestCheckRowButtonStyle())
            .accessibilityLabel("\(check.name), \(stateAccessibilityName)")
            .accessibilityHint("Opens the check's details page")
        } else {
            rowContent(showsLinkGlyph: false)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
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

/// Full-width row button with the shared selectable-row hover and pressed fills.
/// The rows sit in a plain `VStack`, so the fill renders as a direct background
/// instead of going through `listRowBackground`.
private struct PullRequestCheckRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        PullRequestCheckRowButtonBody(configuration: configuration)
    }
}

private struct PullRequestCheckRowButtonBody: View {
    let configuration: ButtonStyle.Configuration

    @State private var isHovering = false

    var body: some View {
        configuration.label
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                AppSelectionRowBackground(
                    isSelected: false,
                    isPressed: configuration.isPressed,
                    isHovered: isHovering,
                    leadingInset: 0,
                    trailingInset: 0,
                    topInset: 0,
                    bottomInset: 0
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous))
            .onHover { hovering in
                withAnimation(.easeOut(duration: 0.12)) {
                    isHovering = hovering
                }
            }
    }
}
