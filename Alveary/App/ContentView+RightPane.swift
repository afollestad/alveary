import SwiftUI

enum RightPaneDestination: Hashable {
    case diff
    case skills(SkillsPaneTarget)
    case mcp(MCPPaneTarget)
    case scheduled(ScheduledTaskPaneTarget)

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
        }
    }

    static func resolve(
        selection: SidebarItem?,
        skillsTarget: SkillsPaneTarget?,
        mcpTarget: MCPPaneTarget?,
        scheduledTarget: ScheduledTaskPaneTarget?,
        isDiffViewerRequested: Bool
    ) -> RightPaneDestination? {
        let contextualDestination: RightPaneDestination?
        switch selection {
        case .skills:
            contextualDestination = skillsTarget.map(RightPaneDestination.skills)
        case .mcp:
            contextualDestination = mcpTarget.map(RightPaneDestination.mcp)
        case .scheduled:
            contextualDestination = scheduledTarget.map(RightPaneDestination.scheduled)
        default:
            contextualDestination = nil
        }
        return contextualDestination ?? (isDiffViewerRequested ? .diff : nil)
    }
}

enum RightPaneWidthDomain: Hashable {
    case diff
    case skills
    case mcp
    case scheduled
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

    init(settings: AppSettings) {
        diff = CGFloat(settings.diffViewerWidth)
        skills = CGFloat(settings.skillsPaneWidth)
        mcp = CGFloat(settings.mcpPaneWidth)
        scheduled = CGFloat(settings.scheduledTasksPaneWidth)
    }
}

extension ContentView {
    var rightPaneDestination: RightPaneDestination? {
        RightPaneDestination.resolve(
            selection: appState.selectedSidebarItem,
            skillsTarget: skillsViewModel.activePaneTarget,
            mcpTarget: mcpViewModel.activePaneTarget,
            scheduledTarget: scheduledTasksViewModel.activePaneTarget,
            isDiffViewerRequested: appState.isDiffViewerRequested
        )
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
                }
            },
            set: { width in
                switch domain {
                case .diff: rightPaneWidths.diff = width
                case .skills: rightPaneWidths.skills = width
                case .mcp: rightPaneWidths.mcp = width
                case .scheduled: rightPaneWidths.scheduled = width
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
                onCommitRequested: presentGitCommitModal
            )
        case .skills(let target):
            SkillsPane(viewModel: skillsViewModel, target: target, onDismiss: onDismiss)
        case .mcp(let target):
            MCPServerPane(viewModel: mcpViewModel, target: target, onDismiss: onDismiss)
        case .scheduled(let target):
            ScheduledTaskEditorPane(viewModel: scheduledTasksViewModel, target: target, onDismiss: onDismiss)
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
        case .showDiff:
            appState.showDiffViewer()
        case .deactivateContextAndShowDiff(.diff):
            assertionFailure("Diff is not a contextual pane")
        }
    }

    func handleRightPaneDestinationChange(_ destination: RightPaneDestination?) {
        let isDiffVisible = destination == .diff
        diffViewModel.setWatchingEnabled(isDiffVisible)
        updateDiffViewer(item: appState.selectedSidebarItem)
    }
}
