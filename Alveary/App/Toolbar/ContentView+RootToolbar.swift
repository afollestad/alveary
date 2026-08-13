import SwiftUI

/// The main window's two app-owned toolbar items, kept out of `ContentView.body`
/// so the button group's arguments type-check on their own; see the type-check
/// budget bullets in `Alveary/Views/AGENTS.md`.
extension ContentView {
    @ToolbarContentBuilder
    var rootToolbarContent: some ToolbarContent {
        ToolbarItem(id: MainWindowToolbarItemID.header, placement: .navigation) {
            MainPaneToolbarHeader(
                presentation: MainPaneHeaderPresentation(
                    selection: appState.selectedSidebarItem,
                    modelContext: uiModelContext
                ),
                onNewConversation: headerNewConversationAction
            )
            .padding(.leading, MainPaneToolbarLayout.leadingPadding)
        }
        .sharedBackgroundVisibility(.hidden)

        ToolbarSpacer(.flexible)

        ToolbarItem(id: MainWindowToolbarItemID.actions, placement: .primaryAction) {
            primaryToolbarButtonGroup
        }
        .sharedBackgroundVisibility(.hidden)
    }

    private var primaryToolbarButtonGroup: some View {
        PrimaryToolbarButtonGroup(
            isSelectionProjectActionCapable: toolbarProjectActionsSelection.isProjectActionCapable,
            projectActions: toolbarProjectActions,
            projectActionsOwner: toolbarProjectActionsOwner,
            terminalTitle: terminalToggleTitle,
            terminalDisplayState: terminalToolbarDisplayState,
            terminalHelpText: "\(terminalToggleTitle) (\(KeyboardShortcut.toggleTerminalPane.displayString))",
            pullRequestState: pullRequestLinksToolbarState,
            pullRequestHelpText: pullRequestToolbarHelpText,
            isPullRequestPopoverPresented: $isPullRequestPopoverPresented,
            diffDisplayState: diffViewerToolbarDisplayState,
            diffHelpText: diffViewerToggleHelpText
                + " (\(KeyboardShortcut.toggleDiffViewer.displayString))",
            diffAccessibilityLabel: isDiffViewerRendered ? "Hide Diff Viewer" : "Show Diff Viewer",
            diffAccessibilityValue: diffViewerToggleAccessibilityValue,
            settingsBadgeState: appUpdateManager.toolbarBadgeState,
            onProjectAction: { owner, action in
                runProjectAction(owner: owner, action: action)
            },
            onToggleTerminal: toggleTerminalPane,
            onPullRequestAction: performPullRequestToolbarAction,
            onPullRequestSecondaryAction: presentPullRequestPopover,
            pullRequestPopoverContent: { AnyView(pullRequestPopoverContent()) },
            onToggleDiffViewer: toggleDiffViewer,
            onOpenSettings: {
                appState.openSettings(targetPage: appUpdateManager.toolbarBadgeState.settingsTargetPage)
            }
        )
        .padding(.trailing, MainPaneToolbarLayout.trailingPadding)
    }
}
