import SwiftUI

extension SidebarView {
    func activeThreads(for project: Project) -> [AgentThread] {
        project.threads
            .filter { $0.archivedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func spacingBeforeProject(at index: Int, in projects: [Project]) -> CGFloat {
        guard index > 0 else {
            return 0
        }

        let previousProject = projects[index - 1]
        let previousActiveThreads = activeThreads(for: previousProject)
        let previousArchivedThreads = archivedThreads(for: previousProject)
        let hasExpandedContent = !previousActiveThreads.isEmpty || !previousArchivedThreads.isEmpty

        guard expandedProjects.contains(previousProject.path), hasExpandedContent else {
            return 0
        }

        return 8
    }

    func topLevelRow(title: String, systemImage: String, item: SidebarItem) -> some View {
        Label(title, systemImage: systemImage)
            .frame(maxWidth: .infinity, alignment: .leading)
            .appSelectableRow(
                isSelected: appState.selectedSidebarItem == item,
                action: { appState.selectedSidebarItem = item }
            )
    }

    func archivedThreads(for project: Project) -> [AgentThread] {
        project.threads
            .filter { $0.archivedAt != nil }
            .sorted { lhs, rhs in
                let leftDate = lhs.archivedAt ?? .distantPast
                let rightDate = rhs.archivedAt ?? .distantPast
                return leftDate > rightDate
            }
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
    }

    func activateThread(_ thread: AgentThread) {
        appState.selectedSidebarItem = .thread(thread)
    }

    func syncExpansionWithSelection(_ item: SidebarItem?) {
        switch item {
        case .project(let project):
            expandedProjects.insert(project.path)
        case .thread(let thread):
            if let projectPath = thread.project?.path {
                expandedProjects.insert(projectPath)
            }
        default:
            break
        }
    }
}
