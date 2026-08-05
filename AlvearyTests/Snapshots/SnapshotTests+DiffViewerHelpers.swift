import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func primaryToolbarButtonGroup(
        selectedThread: AgentThread? = nil,
        // A selected project row owns its actions by path; pass this instead of
        // `selectedThread` to render the project-row case.
        selectedProjectPath: String? = nil,
        projectActions: [AlvearyProjectConfig.ProjectAction] = [],
        terminalDisplayState: TerminalToolbarDisplayState = .idle,
        // Nil matches the pre-existing baselines: no thread selected means no
        // pull-request button.
        pullRequestState: PullRequestLinksToolbarState? = nil,
        settingsBadgeState: AppUpdateToolbarBadgeState = .none,
        diffDisplayState: DiffViewerToolbarDisplayState
    ) -> some View {
        let owner = selectedThread.map { ToolbarProjectActionsOwner.thread($0.persistentModelID) }
            ?? selectedProjectPath.map { ToolbarProjectActionsOwner.project($0) }
        return PrimaryToolbarButtonGroup(
            isSelectionProjectActionCapable: owner != nil,
            projectActions: projectActions,
            projectActionsOwner: owner,
            terminalTitle: "Show Terminal",
            terminalDisplayState: terminalDisplayState,
            terminalHelpText: "Show Terminal (\(KeyboardShortcut.toggleTerminalPane.displayString))",
            pullRequestState: pullRequestState,
            pullRequestHelpText: "Link a pull request (\(KeyboardShortcut.togglePullRequests.displayString))",
            isPullRequestPopoverPresented: .constant(false),
            diffDisplayState: diffDisplayState,
            diffHelpText: "Show Diff Viewer (\(KeyboardShortcut.toggleDiffViewer.displayString))",
            diffAccessibilityLabel: "Show Diff Viewer",
            diffAccessibilityValue: "",
            settingsBadgeState: settingsBadgeState,
            onProjectAction: { _, _ in },
            onToggleTerminal: {},
            onPullRequestAction: {},
            onPullRequestSecondaryAction: {},
            pullRequestPopoverContent: { AnyView(EmptyView()) },
            onToggleDiffViewer: {},
            onOpenSettings: {}
        )
    }
}
