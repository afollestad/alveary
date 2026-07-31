import SwiftData
import SwiftUI

/// Toolbar-side state and actions for the selected thread's or project's linked
/// pull requests.
extension ContentView {
    /// The sidebar selection a link would belong to: a non-draft thread or a
    /// project. Nil for every other selection, which hides the toolbar button.
    var selectedPullRequestLinkOwner: PullRequestLinkOwner? {
        switch appState.selectedSidebarItem {
        case .thread(let thread) where !thread.isDraft:
            return .thread(thread.persistentModelID)
        case .project(let project):
            return .project(project.persistentModelID)
        default:
            return nil
        }
    }

    /// The selected owner's links, read straight off the model so the toolbar
    /// and popover both follow linking and unlinking. A project aggregates its
    /// own links with its child threads' (each row carrying its true owner).
    /// These are observation-tracked relationship reads, not fetches, so they
    /// are safe as render-time sources — see the fetch-backed-gate rule in
    /// `App/AGENTS.md`.
    var selectedPullRequestLinks: [OwnedPullRequestLink] {
        switch appState.selectedSidebarItem {
        case .thread(let thread) where !thread.isDraft:
            let owner = PullRequestLinkOwner.thread(thread.persistentModelID)
            return thread.linkedPullRequests.map {
                OwnedPullRequestLink(link: $0, owner: owner)
            }
        case .project(let project):
            return project.aggregatedPullRequestLinks
        default:
            return []
        }
    }

    /// Nil hides the toolbar button: no thread or project selected, or the
    /// integration off.
    var pullRequestLinksToolbarState: PullRequestLinksToolbarState? {
        guard settingsService.current.pullRequestsEnabled, selectedPullRequestLinkOwner != nil else {
            return nil
        }
        return PullRequestLinksToolbarState(links: selectedPullRequestLinks.map(\.link))
    }

    /// The live status of the pull request whose pane the selection has open.
    ///
    /// Reads the session's `summary`, not its `detail`: close, reopen, and
    /// mark-ready apply optimistically to the summary and only reach `detail`
    /// after the refetch, so watching `detail` would lag every state change by a
    /// round trip. The same refetch settles the summary afterwards (a reopened
    /// draft comes back `.draft`), so this both reacts instantly and stays right.
    var activeSelectionPullRequestStatus: PullRequestStatus? {
        guard let owner = selectedPullRequestLinkOwner,
              let target = pullRequestsViewModel.activePaneTarget(for: PullRequestPaneOrigin(owner: owner)) else {
            return nil
        }
        return pullRequestsViewModel.paneSessions[target]?.summary.status
    }

    /// The stored snapshot is a cache, so reconcile it as soon as the open pane
    /// knows better rather than waiting for the next open. The write goes to the
    /// rendered row's true owner, which on a project selection may be a child
    /// thread rather than the project itself.
    func persistActiveSelectionPullRequestStatus() {
        guard let selection = selectedPullRequestLinkOwner,
              let target = pullRequestsViewModel.activePaneTarget(for: PullRequestPaneOrigin(owner: selection)),
              let status = pullRequestsViewModel.paneSessions[target]?.summary.status,
              let row = selectedPullRequestLinks.first(where: { $0.id == target.identifier }) else {
            return
        }
        pullRequestLinksViewModel.applyStatus(status, to: target.identifier, owner: row.owner)
    }

    var pullRequestToolbarHelpText: String {
        let base = pullRequestLinksToolbarState?.helpText ?? "Link a pull request"
        return "\(base) (\(KeyboardShortcut.togglePullRequests.displayString))"
    }

    /// Left-click and the ⇧⌘P menu item. A lone link opens its pane; anything
    /// else needs the popover, either to disambiguate or to collect a URL.
    func performPullRequestToolbarAction() {
        guard let state = pullRequestLinksToolbarState else {
            return
        }
        guard state.opensPaneDirectly,
              let owner = selectedPullRequestLinkOwner,
              let row = selectedPullRequestLinks.first else {
            presentPullRequestPopover()
            return
        }
        // With one link the button is a toggle, matching the Diff Viewer button
        // beside it: a second press collapses the pane it just opened.
        guard pullRequestsViewModel.activePaneTarget(for: PullRequestPaneOrigin(owner: owner)) != .details(row.id) else {
            pullRequestsViewModel.deactivatePane()
            return
        }
        openLinkedPullRequest(row)
    }

    /// Secondary click. Always the popover, so an additional pull request can be
    /// linked even while one already resolves the primary action to the pane.
    func presentPullRequestPopover() {
        guard pullRequestLinksToolbarState != nil else {
            return
        }
        pullRequestLinksViewModel.clearLinkError()
        isPullRequestPopoverPresented = true
    }

    func openLinkedPullRequest(_ row: OwnedPullRequestLink) {
        guard let selection = selectedPullRequestLinkOwner else {
            return
        }
        isPullRequestPopoverPresented = false
        // The two panes share one lane and must replace each other. A contextual
        // target only *masks* a requested Diff Viewer, so without clearing the
        // request, closing this pane would reveal the Diff Viewer underneath —
        // the mirror of `toggleDiffViewer` deactivating this pane.
        appState.hideDiffViewer()
        // The origin is the *selection* surface — a project selection scopes the
        // pane even when the row's link is stored on a child thread.
        pullRequestsViewModel.requestDetails(row.link.summary, origin: PullRequestPaneOrigin(owner: selection))
        // The stored summary is a cache; opening is the moment to reconcile it,
        // so the toolbar glyph follows merges and closures. The refresh targets
        // the row's true owner.
        Task {
            await pullRequestLinksViewModel.refreshSnapshot(row.id, owner: row.owner)
        }
    }

    @ViewBuilder
    func pullRequestPopoverContent() -> some View {
        if let owner = selectedPullRequestLinkOwner {
            PullRequestLinksPopover(
                links: selectedPullRequestLinks,
                isLinking: pullRequestLinksViewModel.isLinking,
                errorMessage: pullRequestLinksViewModel.linkErrorMessage,
                showsGitSettingsAction: pullRequestLinksViewModel.linkFailureNeedsGitSettings,
                onOpen: { row in
                    openLinkedPullRequest(row)
                },
                onRemove: { row in
                    pullRequestLinksViewModel.unlink(row.id, owner: row.owner)
                },
                onLink: { urlText in
                    Task {
                        await pullRequestLinksViewModel.link(urlText: urlText, owner: owner)
                    }
                },
                onOpenGitSettings: {
                    isPullRequestPopoverPresented = false
                    appState.openSettings(targetPage: .git)
                },
                onEditURL: pullRequestLinksViewModel.clearLinkError
            )
        }
    }
}
