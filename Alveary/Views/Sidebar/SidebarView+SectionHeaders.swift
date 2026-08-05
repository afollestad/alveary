import SwiftUI

extension SidebarView {
    func projectsHeader(isListSectionHeader: Bool) -> some View {
        SidebarSectionHeaderRow(
            title: "Projects",
            showsTopDivider: isListSectionHeader,
            isListSectionHeader: isListSectionHeader,
            disclosure: sectionDisclosure(.projects),
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            onAddProject: { appState.openNewProjectFlow() }
        )
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
            disclosure: sectionDisclosure(.tasks),
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            onAction: { startNewTaskFlowFromSidebar(appState: appState) }
        )
        .sidebarDragGeometry(
            .tasksHeader,
            excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
        )
    }

    func isSectionExpanded(_ section: SidebarCollapsibleSection) -> Bool {
        !collapsedSections.contains(section)
    }

    private func sectionDisclosure(_ section: SidebarCollapsibleSection) -> SidebarSectionHeaderDisclosure {
        SidebarSectionHeaderDisclosure(
            isExpanded: isSectionExpanded(section),
            onToggle: { toggleSectionCollapsedFromHeader(section) }
        )
    }

    private func toggleSectionCollapsedFromHeader(_ section: SidebarCollapsibleSection) {
        guard !isSidebarDragInteractionInFlight else {
            return
        }
        if collapsedSections.contains(section) {
            collapsedSections.remove(section)
        } else {
            collapsedSections.insert(section)
        }
        claimSidebarFocus()
    }
}

/// A sidebar section the user can collapse from its header. `Pinned` is deliberately absent: it
/// heads a group whose whole point is to stay in view.
enum SidebarCollapsibleSection: Hashable {
    case projects
    case tasks

    /// The section a completed drop landed in, or nil when the drop cannot be hidden by a collapse.
    init?(dropSection: SidebarDropSection) {
        switch dropSection {
        case .projects:
            self = .projects
        case .tasks:
            self = .tasks
        case .pinned:
            return nil
        }
    }
}
