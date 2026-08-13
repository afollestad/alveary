import SwiftUI

struct PullRequestsScreen: View {
    @Bindable var viewModel: PullRequestsViewModel
    let onOpenGitSettings: () -> Void

    @FocusState private var isListFocused: Bool

    private let contentVerticalPadding: CGFloat = 28
    // Match the new-thread hero's optical center within the Pull Requests pane.
    private let emptyStateVerticalOffset: CGFloat = -91

    var body: some View {
        attachmentAccessSheet(
            VStack(spacing: 0) {
                PullRequestsScreenHeader(viewModel: viewModel)

                content
            }
            .task {
                await viewModel.refreshForScreen()
            }
        )
    }

    /// Lifted out of `body` to keep the presentation modifier off the
    /// type-check budget, like `PullRequestPane`'s delete dialog.
    private func attachmentAccessSheet<Content: View>(_ content: Content) -> some View {
        content.sheet(item: $viewModel.attachmentAccessRequest) { _ in
            PullRequestAttachmentAccessSheet(
                onOpenSettings: { GitHubAttachmentAccessGuide.openFullDiskAccessSettings() },
                onRetry: { viewModel.retryAttachmentUpload() },
                onCancel: { viewModel.dismissAttachmentAccessRequest() }
            )
        }
    }

    @ViewBuilder
    private var content: some View {
        switch viewModel.loadPhase {
        case .unavailable(let reason):
            PullRequestsUnavailableState(
                reason: reason,
                onOpenGitSettings: onOpenGitSettings,
                onRetry: { viewModel.retry() }
            )
        case .idle, .loading:
            StatusIndicatorSpinner(color: .secondary, diameter: 16, lineWidth: 2)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Loading pull requests")
        case .loaded:
            listContent
        }
    }

    private var listContent: some View {
        // Resolved once per body pass rather than inside the scroll content: that closure
        // re-runs on every geometry change, so the filter/sort/bucket pipeline used to run
        // again for each frame of the right pane's slide-in.
        let sections = viewModel.visibleSections(for: viewModel.selectedFilter)
        let activeDetailID = viewModel.activeDetailIdentifier
        let showsRepository = viewModel.showsRepositoryInRows
        let referenceDate = viewModel.referenceDate
        let avatarLoader = viewModel.avatarLoader
        let canLoadMore = viewModel.canLoadMore(for: viewModel.selectedFilter)
        let isLoadingMore = viewModel.isLoadingMore
        return GeometryReader { proxy in
            ScrollViewReader { scrollProxy in
                ScrollView {
                    ZStack(alignment: .topLeading) {
                        if sections.isEmpty {
                            PullRequestsEmptyState(
                                filter: viewModel.selectedFilter,
                                hasActiveNarrowing: viewModel.hasActiveNarrowing
                            )
                            .offset(y: emptyStateVerticalOffset)
                        }

                        VStack(alignment: .leading, spacing: 24) {
                            banners

                            if !sections.isEmpty {
                                PullRequestsSectionedList(
                                    sections: sections,
                                    showsRepository: showsRepository,
                                    referenceDate: referenceDate,
                                    avatarLoader: avatarLoader,
                                    activeDetailID: activeDetailID,
                                    onSelect: { summary in
                                        viewModel.requestDetails(summary)
                                        isListFocused = true
                                    }
                                )
                                .equatable()

                                // `canLoadMore` goes false the moment a page is requested — its
                                // buckets are in flight — so `isLoadingMore` is what keeps the
                                // footer mounted long enough to show its spinner.
                                if canLoadMore || isLoadingMore {
                                    PullRequestsLoadMoreFooter(
                                        isLoading: isLoadingMore,
                                        onLoadMore: { viewModel.requestLoadMore() }
                                    )
                                    .equatable()
                                }
                            }
                        }
                    }
                    .frame(minHeight: max(proxy.size.height - (contentVerticalPadding * 2), 0), alignment: .top)
                    .padding(
                        EdgeInsets(
                            top: contentVerticalPadding,
                            leading: PaneHeaderLayout.leadingInset,
                            bottom: contentVerticalPadding,
                            trailing: PaneHeaderLayout.trailingInset
                        )
                    )
                }
                .focusable()
                .focusEffectDisabled()
                .focused($isListFocused)
                .onKeyPress(.upArrow) {
                    moveSelection(forward: false, scrollProxy: scrollProxy)
                }
                .onKeyPress(.downArrow) {
                    moveSelection(forward: true, scrollProxy: scrollProxy)
                }
                // The fixed filters can be changed at any scroll depth; each result set starts at the top.
                .id(viewModel.selectedFilter.id)
            }
        }
        .pullRequestReferenceDateTick(viewModel)
    }

    /// Rows in visual order for the current tab: section order, top to bottom.
    private var orderedVisibleRows: [PullRequestSummary] {
        viewModel.visibleSections(for: viewModel.selectedFilter).flatMap(\.rows)
    }

    private func moveSelection(forward: Bool, scrollProxy: ScrollViewProxy) -> KeyPress.Result {
        guard let selectedID = viewModel.selectAdjacentRow(in: orderedVisibleRows, forward: forward) else {
            return .ignored
        }
        scrollProxy.scrollTo(selectedID)
        return .handled
    }

    @ViewBuilder
    private var banners: some View {
        if let errorMessage = viewModel.errorMessage {
            // Carries its own Retry: this banner renders *over* rows that did load, so the
            // full-screen unavailable state's Retry is not on screen, and the header's refresh
            // icon is not a discoverable recovery from a red banner.
            InlineBanner(
                message: errorMessage,
                severity: .error,
                autoDismissAfter: nil,
                actionTitle: "Retry",
                onAction: viewModel.retry,
                onDismiss: viewModel.clearError
            )
        }
        if let warning = viewModel.warnings.first {
            InlineBanner(
                message: warning,
                severity: .warning,
                autoDismissAfter: nil,
                onDismiss: viewModel.dismissWarnings
            )
        }
    }

}

private struct PullRequestsEmptyState: View {
    let filter: PullRequestsFilter
    let hasActiveNarrowing: Bool

    var body: some View {
        EmptyStateView(
            icon: .octicon(.pullRequest24),
            heading: heading,
            subtext: subtext,
            actions: [],
            iconToHeadingSpacing: 16
        )
        .frame(minHeight: 360)
    }

    private var heading: String {
        if hasActiveNarrowing {
            return "No matching pull requests"
        }
        switch filter {
        case .all:
            return "No pull requests"
        case .reviewing:
            return "Nothing to review"
        case .authored:
            return "No authored pull requests"
        }
    }

    private var subtext: String {
        if hasActiveNarrowing {
            return "Try a different search or filter."
        }
        switch filter {
        case .all:
            return "Pull requests involving you will appear here."
        case .reviewing:
            return "Pull requests waiting for your review will appear here."
        case .authored:
            return "Pull requests you open will appear here."
        }
    }
}

private struct PullRequestsUnavailableState: View {
    let reason: PullRequestsUnavailableReason
    let onOpenGitSettings: () -> Void
    let onRetry: () -> Void

    var body: some View {
        EmptyStateView(
            icon: icon,
            heading: heading,
            subtext: subtext,
            actions: actions
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var icon: String {
        switch reason {
        case .notInstalled, .notAuthenticated:
            return "terminal"
        case .rateLimited, .failed:
            return "exclamationmark.triangle"
        }
    }

    private var heading: String {
        switch reason {
        case .notInstalled:
            return "GitHub CLI not installed"
        case .notAuthenticated:
            return "GitHub sign-in required"
        case .rateLimited:
            return "GitHub rate limit reached"
        case .failed:
            return "Pull requests unavailable"
        }
    }

    private var subtext: String {
        switch reason {
        case .notInstalled:
            return "Install the GitHub CLI (gh) to browse pull requests."
        case .notAuthenticated:
            return "Sign in with the GitHub CLI to browse pull requests."
        case .rateLimited:
            return "GitHub is rate limiting API requests. Try again in a few minutes."
        case .failed(let message):
            return message
        }
    }

    private var actions: [EmptyStateAction] {
        switch reason {
        case .notInstalled, .notAuthenticated:
            return [
                .init(
                    title: "Open Git Settings",
                    systemImage: "gearshape",
                    style: .primary,
                    action: onOpenGitSettings
                )
            ]
        case .rateLimited, .failed:
            return [
                .init(
                    title: "Retry",
                    systemImage: "arrow.clockwise",
                    style: .primary,
                    action: onRetry
                )
            ]
        }
    }
}
