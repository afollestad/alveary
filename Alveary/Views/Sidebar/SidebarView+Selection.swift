import SwiftUI

extension SidebarView {
    func activeThreads(for project: Project) -> [AgentThread] {
        viewModel.activeThreads(for: project)
    }

    func topLevelRow(title: String, systemImage: String, item: SidebarItem) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .appSelectableRow(
                isSelected: appState.selectedSidebarItem == item,
                action: {
                    appState.selectedSidebarItem = item
                    claimSidebarFocus()
                }
            )
    }

    func toggleExpansion(for path: String, in set: inout Set<String>) {
        if set.contains(path) {
            set.remove(path)
        } else {
            set.insert(path)
        }
    }

    func activateProject(_ project: Project) {
        let item = SidebarItem.project(project)
        if appState.selectedSidebarItem == item {
            toggleExpansion(for: project.path, in: &expandedProjects)
        } else {
            appState.selectedSidebarItem = item
        }
        claimSidebarFocus()
    }

    func activateThread(_ thread: AgentThread) {
        appState.selectedSidebarItem = .thread(thread)
        claimSidebarFocus()
    }

    func syncExpansionWithSelection(_ item: SidebarItem?) {
        switch item {
        case .project(let project):
            expandedProjects.insert(project.path)
        case .thread(let thread):
            if let projectPath = uiModelContext.resolveThread(id: thread.persistentModelID)?.project?.path {
                expandedProjects.insert(projectPath)
            }
        default:
            break
        }
    }
}
