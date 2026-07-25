import SwiftUI

extension SidebarView {
    func projectsHeader(isListSectionHeader: Bool) -> some View {
        SidebarSectionHeaderRow(
            title: "Projects",
            showsTopDivider: isListSectionHeader,
            isListSectionHeader: isListSectionHeader
        ) {
            appState.openNewProjectFlow()
        }
        .sidebarDragGeometry(
            .projectsHeader,
            excludingTopInset: SidebarProjectListMetrics.listHeaderDragTopInsetExclusion
        )
    }

    var pinnedHeader: some View {
        SidebarSectionHeaderRow(title: "Pinned", showsTopDivider: true)
            .sidebarDragGeometry(
                .pinnedHeader,
                excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTopPaddingCorrection
            )
    }

    var tasksHeader: some View {
        SidebarSectionHeaderRow(
            title: "Tasks", showsTopDivider: true,
            actionSystemImage: "plus",
            actionAccessibilityLabel: "New task",
            actionHelp: "New task",
            onAction: { startNewTaskFlowFromSidebar(appState: appState) }
        )
        .sidebarDragGeometry(
            .tasksHeader,
            excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
        )
    }
}
