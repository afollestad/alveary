import SwiftUI

enum PullRequestPaneTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case files = "Changes"

    var id: String { rawValue }
}

/// The pane compares equal across the lane's own render passes so a resize drag or an
/// unrelated root invalidation cannot rebuild the whole detail subtree. Its body still
/// reads `paneSessions`, so a write to the displayed session re-renders it as before.
struct PullRequestPane: View, Equatable {
    let viewModel: PullRequestsViewModel
    let target: PullRequestPaneTarget
    let onDismiss: () -> Void
    /// Snapshot hosts only, so a baseline can render one tab with the other mounted
    /// behind it; production panes mount the Changes tab on its first visit.
    let initiallyMountedTabs: Set<PullRequestPaneTab>

    @State private var selectedTab: PullRequestPaneTab

    init(
        viewModel: PullRequestsViewModel,
        target: PullRequestPaneTarget,
        onDismiss: @escaping () -> Void,
        initialSelectedTab: PullRequestPaneTab = .overview,
        initiallyMountedTabs: Set<PullRequestPaneTab> = []
    ) {
        self.viewModel = viewModel
        self.target = target
        self.onDismiss = onDismiss
        self.initiallyMountedTabs = initiallyMountedTabs
        _selectedTab = State(initialValue: initialSelectedTab)
    }

    /// `onDismiss` is excluded: `ResizableRightPane` keys the pane by presentation
    /// identity, so a fresh closure meaning something different arrives only with a
    /// new `.id` — which tears this view down instead of comparing it. The tab seeds
    /// are excluded with it; both only prime `@State` at mount.
    nonisolated static func == (lhs: PullRequestPane, rhs: PullRequestPane) -> Bool {
        lhs.viewModel === rhs.viewModel && lhs.target == rhs.target
    }

    var body: some View {
        commentScrollObserver(deleteCommentDialog(missingProjectAlert(
            VStack(spacing: 0) {
                ContextualPaneHeader(
                    target.identifier.displayKey,
                    closeAccessibilityLabel: "Close pull request details",
                    onClose: onDismiss
                )

                if let session = viewModel.paneSessions[target] {
                    tabRow

                    content(session: session)

                    PullRequestPaneReviewFooter(viewModel: viewModel, session: session, target: target)
                        .equatable()
                } else {
                    // The session is discarded after the slide-out; keep the frame stable meanwhile.
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .pullRequestReferenceDateTick(viewModel)
        )))
    }

    /// The address-feedback route refuses outright when no project holds the pull request's
    /// repository — it edits and pushes, so a thread with no checkout could not do the job. A modal
    /// rather than the footer's banner because the fix is elsewhere in the app, and dismissing is
    /// the only thing to do here. Lifted out of `body` like the dialog above, for the type-check
    /// budget.
    private func missingProjectAlert<Content: View>(_ content: Content) -> some View {
        content.alert(
            "Project not added",
            isPresented: Binding(
                get: { viewModel.paneSessions[target]?.agenticThreadMissingProject != nil },
                set: { isPresented in
                    if !isPresented {
                        viewModel.clearAgenticThreadMissingProject()
                    }
                }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearAgenticThreadMissingProject()
            }
        } message: {
            Text(missingProjectMessage)
        }
    }

    /// Rebuilt from the error rather than respelled here, so the sentence has one author.
    private var missingProjectMessage: String {
        guard let repository = viewModel.paneSessions[target]?.agenticThreadMissingProject else {
            return ""
        }
        return PullRequestAgenticThreadService.StartError
            .projectMissing(repository: repository)
            .localizedDescription
    }

    /// Every ask to reveal a comment lands on the Changes tab, whether it came from a review
    /// proposal's transcript card or the Overview's own "Show in Changes" — so the tab switch
    /// lives here rather than at either call site. `KeepAliveTabContainer` mounts the tab on the
    /// switch, and the diff's own observer performs the scroll once its rows exist.
    ///
    /// Lifted out of `body` to keep the modifier off its type-check budget, like the dialog above.
    private func commentScrollObserver<Content: View>(_ content: Content) -> some View {
        content
            // `task(id:)`, not `onChange`: a jump into a *closed* pane arms the scroll during the
            // same call that opens it, so the token is already set when this view first mounts and
            // a change handler would never see it — leaving the pane on Overview with the Changes
            // tab never mounted, which is the whole of the jump.
            .task(id: viewModel.paneSessions[target]?.pendingCommentScrollTarget?.token) {
                guard viewModel.paneSessions[target]?.pendingCommentScrollTarget != nil else {
                    return
                }
                selectedTab = .files
            }
            // A jump routinely lands while the diff is still loading, when there are no files to
            // search; re-run the reveal once they arrive so the row exists to scroll to.
            .onChange(of: viewModel.paneSessions[target]?.diffState) { _, _ in
                viewModel.revealPendingCommentScrollFileIfNeeded(target: target)
            }
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
        // The chips' fill comes from `TabChipButtonStyle`, whose rendered output SwiftUI
        // reuses when a switch changes nothing structural — which is exactly what keeping
        // both tabs mounted made true, leaving the highlight a selection behind.
        .id(selectedTab)
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
        .contextualPaneTrailingGlyphLane(controlWidth: ActionButtonMetrics.iconButtonDiameter)
        .help("Open on GitHub")
        .accessibilityLabel("Open pull request on GitHub")
    }

    /// Prefer the API-provided URL; the constructed fallback covers stale sessions.
    private var pullRequestURL: URL? {
        let session = viewModel.paneSessions[target]
        if let url = session?.detail?.url ?? session?.summary?.url {
            return url
        }
        let id = target.identifier
        return URL(string: "https://github.com/\(id.nameWithOwner)/pull/\(id.number)")
    }

    /// Both tabs stay mounted once visited so their scroll offsets — and the Changes
    /// tab's prepared diff rows, whose rebuild shows a spinner — survive a switch.
    private func content(session: PullRequestPaneSession) -> some View {
        KeepAliveTabContainer(
            tabs: PullRequestPaneTab.allCases,
            selection: selectedTab,
            initiallyMounted: initiallyMountedTabs
        ) { tab in
            switch tab {
            case .overview:
                PullRequestPaneOverview(
                    session: session,
                    viewModel: viewModel,
                    onOpenFiles: { selectedTab = .files }
                )
                .equatable()
            case .files:
                PullRequestPaneFiles(session: session, viewModel: viewModel, target: target)
                    .equatable()
            }
        }
    }
}
