import SwiftUI

extension SidebarView {
    /// One section's header, chosen by identity. Built-ins keep their own trailing affordances;
    /// a custom section has none, so its header is title and caret alone.
    @ViewBuilder
    func sectionHeader(for descriptor: SidebarSectionDescriptor, context: SidebarRenderContext) -> some View {
        let header = Group {
            switch descriptor.id {
            case .pinned:
                pinnedHeader
            case .projects:
                projectsHeader
            case .tasks:
                tasksHeader
            case .custom(let sectionID):
                customSectionHeader(sectionID: sectionID, name: descriptor.name)
            }
        }
        header
            .sidebarDragSource(
                sectionDragConfiguration(for: descriptor.id, logicalOrder: context.dragLogicalOrder)
            )
            // Headers carry no selection fill, so a plain opacity is the whole fade.
            .opacity(sectionGroupOpacity(descriptor.id))
    }

    /// The fade a row inherits while its whole section is the drag source. Rows apply it through
    /// their own opacity parameter — never an outer `.opacity` — so the selection fill that
    /// `listRowBackground` hoists out of the row fades with the content.
    func sectionGroupOpacity(_ sectionID: SidebarSectionID) -> Double {
        activeSidebarDragItem == .section(sectionID) ? 0.48 : 1
    }

    /// The collapse-agnostic fade for a project group row, keyed by the drop section it renders
    /// in — the two ordered sections are also the two draggable ones that contain project rows.
    func sectionGroupOpacityForDropSection(_ dropSection: SidebarDropSection) -> Double {
        switch dropSection {
        case .pinned:
            sectionGroupOpacity(.pinned)
        case .projects:
            sectionGroupOpacity(.projects)
        case .tasks, .customSection, .sectionList:
            1
        }
    }

    var projectsHeader: some View {
        SidebarSectionHeaderRow(
            title: "Projects",
            showsTopDivider: true,
            disclosure: sectionDisclosure(.projects),
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            onAddProject: { appState.openNewProjectFlow() }
        )
        .sidebarDragGeometry(
            .projectsHeader,
            excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
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

    func customSectionHeader(sectionID: String, name: String) -> some View {
        SidebarSectionHeaderRow(
            title: name,
            showsTopDivider: true,
            disclosure: sectionDisclosure(.custom(sectionID)),
            suppressHoverAffordances: isSidebarDragInteractionInFlight,
            editing: SidebarSectionHeaderEditing(
                isEditing: editingSectionID == sectionID,
                onCommit: { submitted in
                    commitSectionRename(sectionID: sectionID, currentName: name, submitted: submitted)
                },
                onCancel: { cancelSectionRename() }
            )
        )
        .sidebarDragGeometry(
            .customSectionHeader(sectionID),
            excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
        )
        // The pointer path is an `NSMenu` popped from the list overlay's `SecondaryClickTarget`,
        // so these rotor actions are the only way VoiceOver reaches the same two commands.
        // `Alveary/Views/Sidebar/SidebarView+SecondaryClickMenus.swift` owns why a `contextMenu`
        // cannot serve this header.
        .accessibilityActions {
            ForEach(
                sidebarSectionContextMenuItems(isInlineEditingActive: isSidebarInlineEditingActive),
                id: \.self
            ) { item in
                switch item {
                case .rename:
                    Button("Rename...") { beginSectionRename(sectionID: sectionID) }
                case .remove:
                    Button("Remove Section...", role: .destructive) {
                        requestSectionRemoval(sectionID: sectionID, name: name)
                    }
                }
            }
        }
    }

    /// Swaps the header's title for its rename field. Shared by the header's `NSMenu` and its
    /// VoiceOver rotor action, so both enter the edit through one path.
    func beginSectionRename(sectionID: String) {
        editingSectionID = sectionID
    }

    /// Arms the removal confirmation. Removal is never immediate — `removeSection(id:)` runs only
    /// after the dialog, because it relocates every member thread.
    func requestSectionRemoval(sectionID: String, name: String) {
        pendingRemoveSection = SidebarPendingSectionRemoval(id: sectionID, name: name)
    }

    func commitSectionRename(sectionID: String, currentName: String, submitted: String) {
        editingSectionID = nil
        guard let newName = sidebarSectionRenameCommitValue(
            initialValue: currentName,
            submittedValue: submitted
        ) else {
            claimSidebarFocus()
            return
        }
        do {
            try viewModel.renameSection(id: sectionID, to: newName)
        } catch {
            viewModel.presentSidebarError(error)
        }
        claimSidebarFocus()
    }

    func cancelSectionRename() {
        editingSectionID = nil
        claimSidebarFocus()
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
    /// A custom section, keyed by `SidebarSection.id` so collapse state survives a rename.
    case custom(String)

    /// The section a completed drop landed in, or nil when the drop cannot be hidden by a collapse.
    init?(dropSection: SidebarDropSection) {
        switch dropSection {
        case .projects:
            self = .projects
        case .tasks:
            self = .tasks
        case .customSection(let id):
            self = .custom(id)
        case .pinned, .sectionList:
            // `Pinned` never collapses, and a section reorder lands no row inside a section.
            return nil
        }
    }

    /// The collapse key for a rendered section, or nil for one that never collapses.
    init?(sectionID: SidebarSectionID) {
        switch sectionID {
        case .projects:
            self = .projects
        case .tasks:
            self = .tasks
        case .custom(let id):
            self = .custom(id)
        case .pinned:
            return nil
        }
    }
}
