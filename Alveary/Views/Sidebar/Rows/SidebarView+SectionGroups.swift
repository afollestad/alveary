import SwiftData
import SwiftUI

/// One rendered section — header plus body — selected by identity from the render snapshot's
/// ordered descriptors. `SidebarView.body` iterates descriptors and calls this, so section order
/// is data rather than statement order.
extension SidebarView {
    @ViewBuilder
    func sectionGroup(_ descriptor: SidebarSectionDescriptor, context: SidebarRenderContext) -> some View {
        switch descriptor.id {
        case .pinned:
            pinnedSectionGroup(context: context)
        case .projects:
            projectsSectionGroup(context: context)
        case .tasks:
            tasksSectionGroup(context: context)
        case .custom(let sectionID):
            customSectionGroup(sectionID: sectionID, name: descriptor.name, context: context)
        }
    }

    /// `Pinned` renders nothing at all while empty — it is the one section whose header is not a
    /// permanent fixture, because an empty pinned list is the common case.
    @ViewBuilder
    private func pinnedSectionGroup(context: SidebarRenderContext) -> some View {
        let pinnedItems = context.pinnedItems
        if !pinnedItems.isEmpty {
            sectionHeader(for: SidebarSectionDescriptor(id: .pinned, name: "Pinned"), context: context)

            ForEach(pinnedItems) { item in
                let topSpacing: CGFloat = item.id == pinnedItems.first?.id
                    ? 0
                    : SidebarRowMetrics.interThreadRowSpacing
                switch item.kind {
                case .project(let project):
                    projectRow(project, topSpacing: topSpacing, dropSection: .pinned, context: context)
                case .thread(let thread):
                    sidebarThreadRow(
                        thread,
                        layout: .topLevel,
                        topSpacing: topSpacing,
                        attention: context.decisionAttention,
                        dragConfiguration: pinnedItemDragConfiguration(
                            for: thread,
                            logicalOrder: context.dragLogicalOrder
                        ),
                        opacity: activeSidebarDragItem == item.dragItem
                            ? 0.48
                            : sectionGroupOpacity(.pinned)
                    )
                    .sidebarDragGeometry(pinnedItemDragGeometryRole(for: thread))
                }
            }
            .transaction { transaction in
                if context.threadOrderAnimation == nil {
                    transaction.disablesAnimations = true
                    transaction.animation = nil
                }
            }
        }
    }

    @ViewBuilder
    private func projectsSectionGroup(context: SidebarRenderContext) -> some View {
        sectionHeader(for: SidebarSectionDescriptor(id: .projects, name: "Projects"), context: context)

        if isSectionExpanded(.projects) {
            projectRows(
                context.regularProjects,
                showsNoProjectsPlaceholder: context.orderedProjects.isEmpty,
                dropSection: .projects,
                context: context
            )
        }
    }

    @ViewBuilder
    private func tasksSectionGroup(context: SidebarRenderContext) -> some View {
        sectionHeader(for: SidebarSectionDescriptor(id: .tasks, name: "Tasks"), context: context)

        if isSectionExpanded(.tasks) {
            taskRows(
                context.activeTaskThreads,
                placeholderLabel: sidebarTasksPlaceholderLabel(
                    activeTaskThreads: context.activeTaskThreads,
                    hasAnyActiveTaskThreads: context.snapshot.hasAnyActiveTaskThreads
                ),
                context: context
            )
        }
    }

    /// A custom section always renders its header, empty or not: it is a container the user made
    /// on purpose, and one that vanished when its last thread left would be undroppable.
    @ViewBuilder
    private func customSectionGroup(
        sectionID: String,
        name: String,
        context: SidebarRenderContext
    ) -> some View {
        sectionHeader(for: SidebarSectionDescriptor(id: .custom(sectionID), name: name), context: context)

        if isSectionExpanded(.custom(sectionID)) {
            customSectionRows(sectionID: sectionID, context: context)
        }
    }

    @ViewBuilder
    private func customSectionRows(sectionID: String, context: SidebarRenderContext) -> some View {
        let threads = context.threads(inCustomSection: sectionID)
        if threads.isEmpty {
            // Publishing the terminal from the placeholder keeps the section's drop container
            // covering the label region, exactly as the `Tasks` placeholder does for its own.
            Text(sidebarCustomSectionPlaceholderLabel())
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
                .sidebarDragGeometry(.customSectionTerminal(sectionID))
        }

        ForEach(Array(threads.enumerated()), id: \.element.persistentModelID) { index, thread in
            sidebarThreadRow(
                thread,
                layout: .topLevel,
                topSpacing: index == 0 ? 0 : SidebarRowMetrics.interThreadRowSpacing,
                attention: context.decisionAttention,
                dragConfiguration: unpinnedTaskDragConfiguration(
                    for: thread,
                    logicalOrder: context.dragLogicalOrder
                ),
                opacity: activeSidebarDragItem == .unpinnedTask(thread.persistentModelID)
                    ? 0.48
                    : sectionGroupOpacity(.custom(sectionID))
            )
            .sidebarDragGeometry(
                .customSectionTerminal(sectionID),
                isEnabled: index == threads.count - 1
            )
        }
        .transaction { transaction in
            if context.threadOrderAnimation == nil {
                transaction.disablesAnimations = true
                transaction.animation = nil
            }
        }
    }
}

/// An empty custom section's label. Unlike `Tasks` there is no "elsewhere" wording to pick
/// between: a custom section holds exactly the threads placed in it.
func sidebarCustomSectionPlaceholderLabel() -> String {
    "No threads"
}
