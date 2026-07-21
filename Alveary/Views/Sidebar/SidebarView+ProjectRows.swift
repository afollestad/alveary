import AppKit
import SwiftData
import SwiftUI

extension SidebarView {
    func activeTaskThreads() -> [AgentThread] {
        viewModel.activeTaskThreads()
    }

    func hasAnyActiveTaskThreads() -> Bool {
        viewModel.hasAnyActiveTaskThreads()
    }

    @ViewBuilder
    func taskRows(
        _ tasks: [AgentThread],
        showsNoTasksPlaceholder: Bool
    ) -> some View {
        if showsNoTasksPlaceholder {
            Text("No tasks")
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
        }

        ForEach(Array(tasks.enumerated()), id: \.element.persistentModelID) { index, task in
            sidebarThreadRow(
                task,
                layout: .topLevel,
                topSpacing: index == 0 ? 0 : SidebarRowMetrics.interThreadRowSpacing
            )
        }
        .transaction { transaction in
            if threadOrderAnimation == nil {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }

    @ViewBuilder
    func projectRows(
        _ visibleProjects: [Project],
        showsNoProjectsPlaceholder: Bool,
        dropSection: SidebarDropSection
    ) -> some View {
        if showsNoProjectsPlaceholder {
            Text("No projects yet")
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding)
        }

        ForEach(Array(visibleProjects.enumerated()), id: \.element.persistentModelID) { index, project in
            let topSpacing: CGFloat = index == 0 ? 0 : SidebarProjectListMetrics.subsequentProjectTopSpacing
            projectRow(project, topSpacing: topSpacing, dropSection: dropSection)
        }
    }

    @ViewBuilder
    func projectRow(
        _ project: Project,
        topSpacing: CGFloat,
        dropSection: SidebarDropSection
    ) -> some View {
        let activeProjectThreads = activeThreads(for: project)
        let showsNoThreadsPlaceholder = shouldShowNoThreadsPlaceholder(
            activeProjectThreads: activeProjectThreads,
            hasAnyActiveThreads: hasAnyActiveThreads(for: project)
        )
        let configuration = SidebarProjectGroupConfiguration(
            project: project,
            section: dropSection,
            isExpanded: expandedProjects.contains(project.path),
            isSelected: isProjectSelected(project),
            isDragged: activeSidebarDragItem == .project(project.persistentModelID),
            activeThreads: activeProjectThreads,
            showsNoThreadsPlaceholder: showsNoThreadsPlaceholder
        )

        projectHeaderRow(configuration, topSpacing: topSpacing)

        if configuration.isExpanded {
            projectChildRows(configuration)
        }
    }

    private func projectHeaderRow(
        _ configuration: SidebarProjectGroupConfiguration,
        topSpacing: CGFloat
    ) -> some View {
        SidebarProjectRow(
            project: configuration.project,
            isExpanded: configuration.isExpanded,
            isSelected: configuration.isSelected,
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            dragConfiguration: projectDragConfiguration(for: configuration.project),
            onToggleExpanded: { toggleProjectExpansionFromRow(configuration.project) },
            onActivate: { activateProjectFromRow(configuration.project) },
            onCreateThread: { createThreadFromProjectRow(configuration.project) }
        )
        // Measure visible content before the outer inter-project spacer used to center shared boundaries.
        .sidebarDragGeometry(configuration.headerRole)
        .sidebarDragGeometry(configuration.terminalRole, isEnabled: configuration.headerIsTerminal)
        .padding(.top, topSpacing)
        .opacity(configuration.opacity)
        .animation(sidebarDragAnimation, value: configuration.opacity)
        .appSelectionRowBackground(
            isSelected: configuration.isSelected,
            showsHoverBackground: !isSidebarDragInteractionInFlight,
            topInset: topSpacing,
            opacity: configuration.opacity
        )
        .contextMenu { projectContextMenu(for: configuration.project) }
    }

    @ViewBuilder
    func projectContextMenu(for project: Project) -> some View {
        Button("New Thread") {
            Task { await createThread(in: project) }
        }

        Button(sidebarProjectPinContextMenuTitle(isPinned: project.isPinned)) {
            setProjectPinned(project, isPinned: !project.isPinned)
        }

        Button("Reveal in Finder...") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: project.path, isDirectory: true)])
        }

        Button("Remove Project...", role: .destructive) {
            pendingDeleteProject = project
        }
    }

    @ViewBuilder
    private func projectChildRows(_ configuration: SidebarProjectGroupConfiguration) -> some View {
        if configuration.showsNoThreadsPlaceholder {
            Text("No threads")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6.75)
                .padding(.leading, SidebarProjectRow.projectNameLeadingInset)
                .allowsHitTesting(false)
                .opacity(configuration.opacity)
                .animation(sidebarDragAnimation, value: configuration.opacity)
                .sidebarDragGeometry(configuration.terminalRole)
        }

        ForEach(configuration.activeThreads, id: \.persistentModelID) { thread in
            let threadTopSpacing: CGFloat = thread.persistentModelID == configuration.firstThreadID
                ? 0
                : SidebarRowMetrics.interThreadRowSpacing
            sidebarThreadRow(
                thread,
                layout: .project,
                topSpacing: threadTopSpacing,
                opacity: configuration.opacity
            )
            .sidebarDragGeometry(
                configuration.terminalRole,
                isEnabled: thread.persistentModelID == configuration.lastThreadID
            )
        }
        .transaction { transaction in
            if threadOrderAnimation == nil {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }

    private func toggleProjectExpansionFromRow(_ project: Project) {
        guard !isSidebarDragInteractionInFlight else {
            return
        }
        toggleExpansion(for: project.path, in: &expandedProjects)
        claimSidebarFocus()
    }

    private func activateProjectFromRow(_ project: Project) {
        guard !isSidebarDragInteractionInFlight else {
            return
        }
        activateProject(project)
    }

    private func createThreadFromProjectRow(_ project: Project) {
        guard !isSidebarDragInteractionInFlight else {
            return
        }
        Task { await createThread(in: project) }
    }
}

func shouldShowNoTasksPlaceholder(
    activeTaskThreads: [AgentThread],
    hasAnyActiveTaskThreads: Bool
) -> Bool {
    activeTaskThreads.isEmpty && !hasAnyActiveTaskThreads
}

private struct SidebarProjectGroupConfiguration {
    let project: Project
    let section: SidebarDropSection
    let isExpanded: Bool
    let isSelected: Bool
    let isDragged: Bool
    let activeThreads: [AgentThread]
    let showsNoThreadsPlaceholder: Bool

    var opacity: Double { isDragged ? 0.48 : 1 }
    var firstThreadID: PersistentIdentifier? { activeThreads.first?.persistentModelID }
    var lastThreadID: PersistentIdentifier? { activeThreads.last?.persistentModelID }
    var headerRole: SidebarDragGeometryRole { .projectHeader(section, project.persistentModelID) }
    var terminalRole: SidebarDragGeometryRole { .projectTerminal(section, project.persistentModelID) }
    var headerIsTerminal: Bool {
        !isExpanded || (!showsNoThreadsPlaceholder && activeThreads.isEmpty)
    }
}
