import SwiftData
import SwiftUI

enum RightPaneDestination: Hashable {
    case diff
    case skills(SkillsPaneTarget)
    case mcp(MCPPaneTarget)
    case scheduled(ScheduledTaskPaneTarget)
    case pullRequest(PullRequestPaneTarget)

    var widthDomain: RightPaneWidthDomain {
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
            // A thread's or project's linked pull requests open in the same
            // lane. Origin scoping happens where `targets` is built, so this
            // branch stays a pure function of its inputs.
            contextualDestination = targets.pullRequest.map(RightPaneDestination.pullRequest)
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

enum RightPaneWidthDomain: Hashable {
    case diff
    case skills
    case mcp
    case scheduled
    case pullRequests
}

enum DiffViewerCommandIntent: Equatable {
    case hideDiff
    case showDiff
    case deactivateContextAndShowDiff(RightPaneWidthDomain)

    static func resolve(destination: RightPaneDestination?) -> DiffViewerCommandIntent {
        switch destination {
        case .diff:
            .hideDiff
        case .skills:
            .deactivateContextAndShowDiff(.skills)
        case .mcp:
            .deactivateContextAndShowDiff(.mcp)
        case .scheduled:
            .deactivateContextAndShowDiff(.scheduled)
        case .pullRequest:
            .deactivateContextAndShowDiff(.pullRequests)
        case nil:
            .showDiff
        }
    }
}

struct RightPaneWidths {
    var diff: CGFloat
    var skills: CGFloat
    var mcp: CGFloat
    var scheduled: CGFloat
    var pullRequests: CGFloat

    init(settings: AppSettings) {
        diff = CGFloat(settings.diffViewerWidth)
        skills = CGFloat(settings.skillsPaneWidth)
        mcp = CGFloat(settings.mcpPaneWidth)
        scheduled = CGFloat(settings.scheduledTasksPaneWidth)
        pullRequests = CGFloat(settings.pullRequestsPaneWidth)
    }
}

extension ContentView {
    var rightPaneDestination: RightPaneDestination? {
        RightPaneDestination.resolve(
            selection: appState.selectedSidebarItem,
            targets: RightPaneContextualTargets(
                skills: skillsViewModel.activePaneTarget,
                mcp: mcpViewModel.activePaneTarget,
                scheduled: scheduledTasksViewModel.activePaneTarget,
                pullRequest: scopedPullRequestPaneTarget
            ),
            isDiffViewerRequested: appState.isDiffViewerRequested
        )
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

    var isDiffViewerRendered: Bool {
        rightPaneDestination == .diff
    }

    var diffViewerCommand: DiffViewerCommand {
        DiffViewerCommand(
            title: isDiffViewerRendered ? "Hide Diff Viewer" : "Show Diff Viewer",
            action: toggleDiffViewer
        )
    }

    func rightPaneWidthBinding(for domain: RightPaneWidthDomain) -> Binding<CGFloat> {
        Binding(
            get: {
                switch domain {
                case .diff: rightPaneWidths.diff
                case .skills: rightPaneWidths.skills
                case .mcp: rightPaneWidths.mcp
                case .scheduled: rightPaneWidths.scheduled
                case .pullRequests: rightPaneWidths.pullRequests
                }
            },
            set: { width in
                switch domain {
                case .diff: rightPaneWidths.diff = width
                case .skills: rightPaneWidths.skills = width
                case .mcp: rightPaneWidths.mcp = width
                case .scheduled: rightPaneWidths.scheduled = width
                case .pullRequests: rightPaneWidths.pullRequests = width
                }
            }
        )
    }

    func persistRightPaneWidth(_ width: CGFloat, domain: RightPaneWidthDomain) {
        settingsService.update {
            switch domain {
            case .diff:
                $0.diffViewerWidth = width
            case .skills:
                $0.skillsPaneWidth = width
            case .mcp:
                $0.mcpPaneWidth = width
            case .scheduled:
                $0.scheduledTasksPaneWidth = width
            case .pullRequests:
                $0.pullRequestsPaneWidth = width
            }
        }
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
                mode: $diffViewerMode,
                onModeCommit: persistDiffViewerMode,
                topSectionFraction: activeDiffViewerTopSectionFraction,
                onTopSectionFractionCommit: { fraction in
                    persistDiffViewerTopSectionFraction(fraction, mode: diffViewerMode)
                },
                onCommitRequested: presentGitCommitModal,
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
