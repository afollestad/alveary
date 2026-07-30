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
        deleteCommentDialog(
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
        )
    }

    /// Shared by both tabs — arming a deletion from the Changes diff or the
    /// Overview timeline presents the same confirmation. Lifted out of `body`
    /// to keep the presentation modifier off the type-check budget.
    private func deleteCommentDialog<Content: View>(_ content: Content) -> some View {
        content.confirmationDialog(
            "Delete comment?",
            isPresented: Binding(
                get: { viewModel.paneSessions[target]?.pendingRemoteCommentDeletion != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.cancelRemoteCommentDeletion()
                    }
                }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                viewModel.confirmRemoteCommentDeletion()
            }
            Button("Cancel", role: .cancel) {
                viewModel.cancelRemoteCommentDeletion()
            }
        } message: {
            Text("The comment is permanently deleted from the pull request on GitHub.")
        }
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
        // Lands the glyph's right edge on the pane's icon column — the close
        // button above (25.5pt inset, measured ink) and the Changes tab's file
        // collapse carets below (26.5pt) — splitting the half-point difference
        // at 26pt. The glyph centers in the style's 30pt frame with ~8.5pt of
        // interior inset and the tab row is inset 16, so 26 - 16 - 8.5 = 1.5.
        .padding(.trailing, 1.5)
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
