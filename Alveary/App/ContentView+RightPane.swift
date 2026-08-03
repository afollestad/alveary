import SwiftData
import SwiftUI

enum RightPaneDestination: Hashable {
    case diff
    case skills(SkillsPaneTarget)
    case mcp(MCPPaneTarget)
    case scheduled(ScheduledTaskPaneTarget)
    case pullRequest(PullRequestPaneTarget)

    var feature: RightPaneFeature {
        switch self {
        case .diff:
            .diff
        case .skills:
            .skills
        case .mcp:
            .mcp
        case .scheduled:
            .scheduled
        case .pullRequest:
            .pullRequests
        }
    }

    static func resolve(
        selection: SidebarItem?,
        targets: RightPaneContextualTargets,
        isDiffViewerRequested: Bool
    ) -> RightPaneDestination? {
        let contextualDestination: RightPaneDestination?
        switch selection {
        case .skills:
            contextualDestination = targets.skills.map(RightPaneDestination.skills)
        case .mcp:
            contextualDestination = targets.mcp.map(RightPaneDestination.mcp)
        case .scheduled:
            contextualDestination = targets.scheduled.map(RightPaneDestination.scheduled)
        case .pullRequests:
            contextualDestination = targets.pullRequest.map(RightPaneDestination.pullRequest)
        case .thread, .project:
            // A thread's linked pull requests and its scheduling-proposal review open in
            // the same lane. Origin scoping happens where `targets` is built, so this
            // branch stays a pure function of its inputs. Review wins: the user just
            // asked for it, and a pull-request pane can be reopened from the footer.
            contextualDestination = targets.scheduled
                .flatMap { target in
                    // A transcript can open a proposal review or an existing task's
                    // editor; creating one is a Scheduled-screen action.
                    guard target != .create else {
                        return nil
                    }
                    return RightPaneDestination.scheduled(target)
                }
                ?? targets.pullRequest.map(RightPaneDestination.pullRequest)
        default:
            contextualDestination = nil
        }
        return contextualDestination ?? (isDiffViewerRequested ? .diff : nil)
    }
}

/// The active contextual-pane target for each sidebar-driven right-pane feature.
struct RightPaneContextualTargets {
    let skills: SkillsPaneTarget?
    let mcp: MCPPaneTarget?
    let scheduled: ScheduledTaskPaneTarget?
    let pullRequest: PullRequestPaneTarget?

    init(
        skills: SkillsPaneTarget? = nil,
        mcp: MCPPaneTarget? = nil,
        scheduled: ScheduledTaskPaneTarget? = nil,
        pullRequest: PullRequestPaneTarget? = nil
    ) {
        self.skills = skills
        self.mcp = mcp
        self.scheduled = scheduled
        self.pullRequest = pullRequest
    }
}

/// Which feature owns the lane. The lane's width is shared across all of them,
/// so this only names the session a command has to deactivate.
enum RightPaneFeature: Hashable {
    case diff
    case skills
    case mcp
    case scheduled
    case pullRequests
}

enum DiffViewerCommandIntent: Equatable {
    case hideDiff
    case showDiff
    case deactivateContextAndShowDiff(RightPaneFeature)

    static func resolve(destination: RightPaneDestination?) -> DiffViewerCommandIntent {
        switch destination {
        case nil:
            .showDiff
        case .diff:
            .hideDiff
        case .some(let contextual):
            // Everything else in the lane is a contextual pane, and its feature
            // is exactly the session that has to be deactivated first.
            .deactivateContextAndShowDiff(contextual.feature)
        }
    }
}

extension ContentView {
    var rightPaneDestination: RightPaneDestination? {
        RightPaneDestination.resolve(
            selection: appState.selectedSidebarItem,
            targets: RightPaneContextualTargets(
                skills: skillsViewModel.activePaneTarget,
                mcp: mcpViewModel.activePaneTarget,
                scheduled: scopedScheduledPaneTarget,
                pullRequest: scopedPullRequestPaneTarget
            ),
            isDiffViewerRequested: appState.isDiffViewerRequested
        )
    }

    /// The scheduled-task editor pane, scoped so a proposal review opened from one
    /// transcript cannot follow the user onto another thread. The Scheduled screen
    /// keeps its own unscoped target.
    private var scopedScheduledPaneTarget: ScheduledTaskPaneTarget? {
        switch appState.selectedSidebarItem {
        case .scheduled:
            // A transcript-opened pane belongs to its thread, not this screen.
            guard scheduledTasksViewModel.proposalPaneOriginThreadID == nil else {
                return nil
            }
            return scheduledTasksViewModel.activePaneTarget
        case .thread(let thread):
            return scheduledTasksViewModel.activeTranscriptPaneTarget(forThreadID: thread.persistentModelID)
        default:
            return nil
        }
    }

    /// The active pull-request pane target, filtered to the surface that opened
    /// it. Disabling the integration withholds it too, so an unreachable pane
    /// cannot stay on screen.
    private var scopedPullRequestPaneTarget: PullRequestPaneTarget? {
        guard settingsService.current.pullRequestsEnabled else {
            return nil
        }
        switch appState.selectedSidebarItem {
        case .pullRequests:
            return pullRequestsViewModel.activePaneTarget(for: .screen)
        case .thread(let thread):
            return pullRequestsViewModel.activePaneTarget(for: .thread(thread.persistentModelID))
        case .project(let project):
            return pullRequestsViewModel.activePaneTarget(for: .project(project.persistentModelID))
        default:
            return nil
        }
    }

    /// Footer ladder gates, all observation-tracked model reads. Create needs
    /// the commit surface (base branch and remote come from the project) plus
    /// zero links; View needs exactly one — several go through the toolbar
    /// popover, which owns that disambiguation.
    private var canCreatePullRequestFromDiffFooter: Bool {
        settingsService.current.pullRequestsEnabled
            && appState.selectedSidebarItem?.canCommitDiffChanges == true
            && selectedPullRequestLinkOwner != nil
            && selectedPullRequestLinks.isEmpty
    }

    private var canViewPullRequestFromDiffFooter: Bool {
        settingsService.current.pullRequestsEnabled
            && selectedPullRequestLinkOwner != nil
            && selectedPullRequestLinks.count == 1
    }

    var isDiffViewerRendered: Bool {
        rightPaneDestination == .diff
    }

    var diffViewerCommand: DiffViewerCommand {
        DiffViewerCommand(
            title: isDiffViewerRendered ? "Hide Diff Viewer" : "Show Diff Viewer",
            action: toggleDiffViewer
        )
    }

    func persistRightPaneWidth(_ width: CGFloat) {
        settingsService.update { $0.rightPaneWidth = width }
    }

    @ViewBuilder
    func rightPaneContent(
        for destination: RightPaneDestination,
        onDismiss: @escaping () -> Void
    ) -> some View {
        switch destination {
        case .diff:
            DiffViewerPane(
                viewModel: diffViewModel,
                // Keep render-time gates observation-tracked; action handlers re-resolve backing rows.
                canCommit: appState.selectedSidebarItem?.canCommitDiffChanges == true,
                canCreatePullRequest: canCreatePullRequestFromDiffFooter,
                canViewPullRequest: canViewPullRequestFromDiffFooter,
                mode: $diffViewerMode,
                onModeCommit: persistDiffViewerMode,
                topSectionFraction: activeDiffViewerTopSectionFraction,
                onTopSectionFractionCommit: { fraction in
                    persistDiffViewerTopSectionFraction(fraction, mode: diffViewerMode)
                },
                onCommitRequested: presentGitCommitModal,
                onCreatePullRequestRequested: presentCreatePullRequestModal,
                onViewPullRequestRequested: openSinglePullRequestFromDiffFooter,
                // The lane's own dismissal, so the header X and ⇧⌘D end in the
                // same place.
                onClose: onDismiss
            )
        case .skills(let target):
            SkillsPane(viewModel: skillsViewModel, target: target, onDismiss: onDismiss)
        case .mcp(let target):
            MCPServerPane(viewModel: mcpViewModel, target: target, onDismiss: onDismiss)
        case .scheduled(let target):
            ScheduledTaskEditorPane(viewModel: scheduledTasksViewModel, target: target, onDismiss: onDismiss)
        case .pullRequest(let target):
            PullRequestPane(viewModel: pullRequestsViewModel, target: target, onDismiss: onDismiss)
                .environment(\.appMarkdownImagePreviewAction, markdownImagePreviewAction)
        }
    }

    /// Routes clicked markdown images in the PR pane (description, comments,
    /// review threads) into the app image preview modal, matching the chat
    /// transcript's behavior. The stable id keeps re-renders from invalidating
    /// the pane's environment.
    private var markdownImagePreviewAction: AppMarkdownImagePreviewAction {
        AppMarkdownImagePreviewAction(id: "app-image-preview-modal") { [appState] image, baseURL in
            appState.presentImagePreview(.markdownImage(image, baseURL: baseURL))
        }
    }

    func rightPanePresentationGeneration(for destination: RightPaneDestination) -> UUID? {
        switch destination {
        case .diff:
            appState.diffViewerRequestID
        case .skills(.newSkill):
            skillsViewModel.newSkillSession?.generation
        case .skills(.details(let skillID)):
            skillsViewModel.detailSessions[skillID]?.generation
        case .mcp(let target):
            mcpViewModel.paneSessions[target]?.generation
        case .scheduled(let target):
            scheduledTasksViewModel.paneSessions[target]?.generation
        case .pullRequest(let target):
            pullRequestsViewModel.paneSessions[target]?.generation
        }
    }

    var rightPaneDismissalRequests: Set<RightPanePresentationIdentity<RightPaneDestination>> {
        var requests = Set<RightPanePresentationIdentity<RightPaneDestination>>()
        requests.formUnion(skillsViewModel.pendingPaneDismissals.map {
            RightPanePresentationIdentity(destination: .skills($0.target), generation: $0.generation)
        })
        requests.formUnion(mcpViewModel.pendingPaneDismissals.map {
            RightPanePresentationIdentity(destination: .mcp($0.target), generation: $0.generation)
        })
        requests.formUnion(scheduledTasksViewModel.pendingPaneDismissals.map {
            RightPanePresentationIdentity(destination: .scheduled($0.target), generation: $0.generation)
        })
        requests.formUnion(pullRequestsViewModel.pendingPaneDismissals.map {
            RightPanePresentationIdentity(destination: .pullRequest($0.target), generation: $0.generation)
        })
        return requests
    }

    func deactivateRightPane(_ destination: RightPaneDestination, generation: UUID) {
        switch destination {
        case .diff:
            guard appState.diffViewerRequestID == generation else {
                return
            }
            appState.hideDiffViewer()
        case .skills(let target):
            skillsViewModel.deactivatePane(target, generation: generation)
        case .mcp(let target):
            mcpViewModel.deactivatePane(target, generation: generation)
        case .scheduled(let target):
            scheduledTasksViewModel.deactivatePane(target, generation: generation)
        case .pullRequest(let target):
            pullRequestsViewModel.deactivatePane(target, generation: generation)
        }
    }

    func dismissRightPane(_ destination: RightPaneDestination, generation: UUID) {
        switch destination {
        case .diff:
            guard appState.diffViewerRequestID == generation else {
                return
            }
            appState.hideDiffViewer()
        case .skills(let target):
            skillsViewModel.dismissPane(
                target,
                generation: generation,
                restoreFocus: rightPaneDestination == nil
            )
        case .mcp(let target):
            mcpViewModel.dismissPane(
                target,
                generation: generation,
                restoreFocus: rightPaneDestination == nil
            )
        case .scheduled(let target):
            scheduledTasksViewModel.dismissPane(
                target,
                generation: generation,
                restoreFocus: rightPaneDestination == nil
            )
        case .pullRequest(let target):
            pullRequestsViewModel.dismissPane(
                target,
                generation: generation,
                restoreFocus: rightPaneDestination == nil
            )
        }
    }

    func toggleDiffViewer() {
        switch DiffViewerCommandIntent.resolve(destination: rightPaneDestination) {
        case .hideDiff:
            appState.hideDiffViewer()
        case .deactivateContextAndShowDiff(.skills):
            skillsViewModel.deactivatePane()
            appState.showDiffViewer()
        case .deactivateContextAndShowDiff(.mcp):
            mcpViewModel.deactivatePane()
            appState.showDiffViewer()
        case .deactivateContextAndShowDiff(.scheduled):
            scheduledTasksViewModel.deactivatePane()
            appState.showDiffViewer()
        case .deactivateContextAndShowDiff(.pullRequests):
            pullRequestsViewModel.deactivatePane()
            appState.showDiffViewer()
        case .showDiff:
            appState.showDiffViewer()
        case .deactivateContextAndShowDiff(.diff):
            assertionFailure("Diff is not a contextual pane")
        }
    }
}
