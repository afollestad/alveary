import SwiftUI

enum PullRequestPaneTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case files = "Changes"

    var id: String { rawValue }
}

struct PullRequestPane: View {
    let viewModel: PullRequestsViewModel
    let target: PullRequestPaneTarget
    let onDismiss: () -> Void

    @State private var selectedTab = PullRequestPaneTab.overview

    var body: some View {
        VStack(spacing: 0) {
            ContextualPaneHeader(
                target.identifier.displayKey,
                closeAccessibilityLabel: "Close pull request details",
                onClose: onDismiss
            )

            if let session = viewModel.paneSessions[target] {
                tabRow

                content(session: session)

                PullRequestPaneReviewFooter(viewModel: viewModel, session: session)
            } else {
                // The session is discarded after the slide-out; keep the frame stable meanwhile.
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var tabRow: some View {
        HStack(spacing: 6) {
            ForEach(PullRequestPaneTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tab.rawValue)
                        .fixedSize(horizontal: true, vertical: false)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                }
                .buttonStyle(TabChipButtonStyle(isSelected: selectedTab == tab))
                .accessibilityAddTraits(selectedTab == tab ? .isSelected : [])
            }

            Spacer(minLength: 0)

            openInBrowserButton
        }
        .contextualPaneHorizontalInsets()
        .padding(.vertical, 10)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Pull request detail section")
        .accessibilityValue(selectedTab.rawValue)
    }

    private var openInBrowserButton: some View {
        Button {
            if let pullRequestURL {
                UIApplicationShim.open(url: pullRequestURL)
            }
        } label: {
            Image(systemName: "arrow.up.right.square")
        }
        .iconActionButtonStyle()
        .help("Open on GitHub")
        .accessibilityLabel("Open pull request on GitHub")
    }

    /// Prefer the API-provided URL; the constructed fallback covers stale sessions.
    private var pullRequestURL: URL? {
        let session = viewModel.paneSessions[target]
        if let url = session?.detail?.url ?? session?.summary.url {
            return url
        }
        let id = target.identifier
        return URL(string: "https://github.com/\(id.nameWithOwner)/pull/\(id.number)")
    }

    @ViewBuilder
    private func content(session: PullRequestPaneSession) -> some View {
        switch selectedTab {
        case .overview:
            PullRequestPaneOverview(
                session: session,
                viewModel: viewModel,
                onOpenFiles: { selectedTab = .files }
            )
        case .files:
            PullRequestPaneFiles(session: session, viewModel: viewModel)
        }
    }
}
