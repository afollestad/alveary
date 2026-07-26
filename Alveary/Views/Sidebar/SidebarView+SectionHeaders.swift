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
            // Exclude the whole top padding, like `Tasks`. The section's container border starts
            // here, so leaving the divider's breathing room in would float it above the title.
            .sidebarDragGeometry(
                .pinnedHeader,
                excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
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
