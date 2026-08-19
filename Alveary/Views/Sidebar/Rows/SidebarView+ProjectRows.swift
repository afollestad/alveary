import AppKit
import SwiftData
import SwiftUI

extension SidebarView {
    @ViewBuilder
    func taskRows(
        _ tasks: [AgentThread],
        placeholderLabel: String?,
        context: SidebarRenderContext
    ) -> some View {
        if let placeholderLabel {
            // Publishing `.tasksTerminal` keeps the Tasks drop container covering the label
            // region; without it an empty body would shrink the unpin target to the header.
            // Leading matches the `Tasks` header's title ink, which sits 5pt left of task-row
            // titles: the placeholder stands in for the section, not for a row in it. `No projects
            // yet` follows the same rule, and the two render together when both are empty.
            Text(placeholderLabel)
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
                .sidebarDragGeometry(.tasksTerminal)
        }

        ForEach(Array(tasks.enumerated()), id: \.element.persistentModelID) { index, task in
            sidebarThreadRow(
                task,
                layout: .topLevel,
                topSpacing: index == 0 ? 0 : SidebarRowMetrics.interThreadRowSpacing,
                conversationStatuses: context.conversationStatuses(for: task.persistentModelID),
                dragConfiguration: unpinnedTaskDragConfiguration(for: task, logicalOrder: context.dragLogicalOrder),
                opacity: activeSidebarDragItem == .unpinnedTask(task.persistentModelID)
                    ? 0.48
                    : sectionGroupOpacity(.tasks)
            )
            .sidebarDragGeometry(.tasksTerminal, isEnabled: index == tasks.count - 1)
        }
        .transaction { transaction in
            if context.threadOrderAnimation == nil {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }

    @ViewBuilder
    func projectRows(
        _ visibleProjects: [Project],
        showsNoProjectsPlaceholder: Bool,
        dropSection: SidebarDropSection,
        context: SidebarRenderContext
    ) -> some View {
        if showsNoProjectsPlaceholder {
            Text("No projects yet")
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
        }

        ForEach(Array(visibleProjects.enumerated()), id: \.element.persistentModelID) { index, project in
            let topSpacing: CGFloat = index == 0 ? 0 : SidebarProjectListMetrics.subsequentProjectTopSpacing
            projectRow(project, topSpacing: topSpacing, dropSection: dropSection, context: context)
        }
    }

    @ViewBuilder
    func projectRow(
        _ project: Project,
        topSpacing: CGFloat,
        dropSection: SidebarDropSection,
        context: SidebarRenderContext
    ) -> some View {
        let activeProjectThreads = context.activeThreads(for: project)
        let showsNoThreadsPlaceholder = shouldShowNoThreadsPlaceholder(
            activeProjectThreads: activeProjectThreads,
            hasAnyActiveThreads: context.hasAnyActiveThreads(for: project)
        )
        let configuration = SidebarProjectGroupConfiguration(
            project: project,
            section: dropSection,
            isExpanded: expandedProjects.contains(project.path),
            isSelected: isProjectSelected(project),
            // A row fades for its own drag or its whole section's; the section fade reaches
            // children and placeholders through the same `configuration.opacity` the row uses.
            isDragged: activeSidebarDragItem == .project(project.persistentModelID)
                || sectionGroupOpacityForDropSection(dropSection) < 1,
            activeThreads: activeProjectThreads,
            showsNoThreadsPlaceholder: showsNoThreadsPlaceholder
        )

        projectHeaderRow(configuration, topSpacing: topSpacing, context: context)

        if configuration.isExpanded {
            projectChildRows(configuration, context: context)
        }
    }

    private func projectHeaderRow(
        _ configuration: SidebarProjectGroupConfiguration,
        topSpacing: CGFloat,
        context: SidebarRenderContext
    ) -> some View {
        SidebarProjectRow(
            projectName: configuration.project.name,
            isExpanded: configuration.isExpanded,
            isSelected: configuration.isSelected,
            hidesWaitingThread: context.projectHidesWaitingThread(path: configuration.project.path),
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            dragConfiguration: projectDragConfiguration(
                for: configuration.project,
                logicalOrder: context.dragLogicalOrder
            ),
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
            pendingDeleteProject = SidebarPendingProjectRemoval(project: project)
        }
    }

    @ViewBuilder
    private func projectChildRows(
        _ configuration: SidebarProjectGroupConfiguration,
        context: SidebarRenderContext
    ) -> some View {
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
            let childDragItem: SidebarDragItem = thread.effectiveMode == .task
                ? .unpinnedTask(thread.persistentModelID)
                : .projectThread(thread.persistentModelID)
            sidebarThreadRow(
                thread,
                layout: .project,
                topSpacing: threadTopSpacing,
                conversationStatuses: context.conversationStatuses(for: thread.persistentModelID),
                // Task children can leave for `Tasks` or pin; Project-mode children drag only to
                // pin. Either way `Pinned` is reached through its whole-section container.
                dragConfiguration: projectChildDragConfiguration(
                    for: thread,
                    logicalOrder: context.dragLogicalOrder
                ),
                opacity: activeSidebarDragItem == childDragItem
                    ? 0.48
                    : configuration.opacity
            )
            .sidebarDragGeometry(
                configuration.terminalRole,
                isEnabled: thread.persistentModelID == configuration.lastThreadID
            )
        }
        .transaction { transaction in
            if context.threadOrderAnimation == nil {
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

/// The label an empty Tasks body shows, or nil while any Task rows are listed. `No tasks` means
/// none exist anywhere; `No tasks here` means every active Task is elsewhere — pinned above, or
/// placed in a project — so a bare header does not read as a broken section.
func sidebarTasksPlaceholderLabel(
    activeTaskThreads: [AgentThread],
    hasAnyActiveTaskThreads: Bool
) -> String? {
    guard activeTaskThreads.isEmpty else {
        return nil
    }
    return hasAnyActiveTaskThreads ? "No tasks here" : "No tasks"
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
