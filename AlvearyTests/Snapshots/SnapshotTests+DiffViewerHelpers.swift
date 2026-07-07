import SwiftUI

@testable import Alveary

extension SnapshotTests {
    func primaryToolbarButtonGroup(
        selectedThread: AgentThread? = nil,
        projectActions: [AlvearyProjectConfig.ProjectAction] = [],
        terminalDisplayState: TerminalToolbarDisplayState = .idle,
        settingsBadgeState: AppUpdateToolbarBadgeState = .none,
        diffDisplayState: DiffViewerToolbarDisplayState
    ) -> some View {
        let selectedThreadID = selectedThread?.persistentModelID
        return PrimaryToolbarButtonGroup(
            selectedThreadID: selectedThreadID,
            projectActions: projectActions,
            projectActionsThreadID: selectedThreadID,
            terminalTitle: "Show Terminal",
            terminalDisplayState: terminalDisplayState,
            terminalHelpText: "Show Terminal (\(KeyboardShortcut.toggleTerminalPane.displayString))",
            diffDisplayState: diffDisplayState,
            diffHelpText: "Show Diff Viewer (\(KeyboardShortcut.toggleDiffViewer.displayString))",
            diffAccessibilityLabel: "Show Diff Viewer",
            diffAccessibilityValue: "",
            settingsBadgeState: settingsBadgeState,
            onProjectAction: { _, _ in },
            onToggleTerminal: {},
            onToggleDiffViewer: {},
            onOpenSettings: {}
        )
    }
}
