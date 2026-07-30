import AppKit
import SwiftData
import SwiftUI

// SF Symbols include leading side bearings; compensate so visible icon ink aligns with the header text.
private let topIconOpticalInset: CGFloat = 4
private let topLevelIconColumnWidth: CGFloat = 19

enum SidebarRowMetrics {
    private static let labelHeight: CGFloat = 16

    static let topLevelAndThreadVerticalPadding: CGFloat = 4
    static let topLevelAndThreadContentHeight: CGFloat = labelHeight + topLevelAndThreadVerticalPadding * 2
    static let topLevelRowSpacing: CGFloat = 4
    static let interThreadRowSpacing: CGFloat = 2
    static let pinnedThreadBoundarySpacing: CGFloat = 12
}

@MainActor
func areProjectsOrdered(_ lhs: Project, _ rhs: Project) -> Bool {
    let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
    if comparison != .orderedSame {
        return comparison == .orderedAscending
    }
    return lhs.path < rhs.path
}

extension SidebarView {
    // Authoritative fetch-backed reads. These are for post-mutation fallbacks such as
    // deletion/archive selection recovery, never for render passes — `SidebarRenderContext`
    // owns everything the click-to-highlight frame needs.
    func activeThreads(for project: Project) -> [AgentThread] {
        viewModel.activeThreads(for: project)
    }

    func pinnedThreads() -> [AgentThread] {
        viewModel.pinnedThreads()
    }

    func pinnedItems() -> [SidebarPinnedItem] {
        viewModel.pinnedItems(projects: projects)
    }

    func activeTaskThreads() -> [AgentThread] {
        viewModel.activeTaskThreads()
    }

    func isProjectSelected(_ project: Project) -> Bool {
        switch appState.selectedSidebarItem {
        case .project(let selectedProject):
            return selectedProject.path == project.path
        case .thread(let thread):
            return thread.effectiveMode == .project && thread.isDraft && thread.project?.path == project.path
        default:
            return false
        }
    }

    func handleDraftProjectChanged(_ notification: Notification) {
        guard let projectPath = notification.userInfo?[ThreadDraftNotificationKey.projectPath] as? String else {
            return
        }
        expandedProjects.insert(projectPath)
        viewModel.threadOrderVersion += 1
    }

    func handleDraftMaterialized(_ notification: Notification) {
        let mode = sidebarDraftMaterializedMode(notification)
        if let projectPath = sidebarProjectPathToExpandAfterDraftMaterialization(notification) {
            expandedProjects.insert(projectPath)
        }
        viewModel.noteDraftMaterialized(mode: mode)
    }

    /// Top-level rows use SF Symbols except where a domain glyph exists only as an
    /// asset, such as the Primer pull-request octicon.
    enum TopLevelIcon {
        case system(String)
        case asset(String)
    }

    @ViewBuilder
    func topLevelRows(context: SidebarRenderContext) -> some View {
        topLevelRow(
            title: "Skills",
            icon: .system("puzzlepiece.extension"),
            item: .skills,
            bottomSpacing: SidebarRowMetrics.topLevelRowSpacing
        )
        topLevelRow(
            title: "MCP",
            icon: .system("server.rack"),
            item: .mcp,
            bottomSpacing: SidebarRowMetrics.topLevelRowSpacing
        )
        topLevelRow(
            title: "Scheduled",
            icon: .system("clock"),
            item: .scheduled,
            bottomSpacing: SidebarRowMetrics.topLevelRowSpacing
        )
        // Whichever row ends the group takes no bottom spacing; the Projects/Pinned
        // header below owns that boundary.
        topLevelRow(
            title: "Pull requests",
            icon: .asset("PullRequestOcticon"),
            item: .pullRequests,
            bottomSpacing: context.hasArchivedThreads ? SidebarRowMetrics.topLevelRowSpacing : 0,
            isTopLevelTerminal: sidebarTopLevelRowIsTerminal(
                .pullRequests,
                hasArchivedThreads: context.hasArchivedThreads
            )
        )
        if context.hasArchivedThreads {
            topLevelRow(
                title: "Archived",
                icon: .system("archivebox"),
                item: .archived,
                isTopLevelTerminal: sidebarTopLevelRowIsTerminal(
                    .archived,
                    hasArchivedThreads: context.hasArchivedThreads
                )
            )
        }
    }

    @ViewBuilder
    private func topLevelIconImage(for icon: TopLevelIcon) -> some View {
        switch icon {
        case .system(let systemImage):
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .renderingMode(.template)
                .font(.system(size: 13, weight: .semibold))
        case .asset(let assetName):
            // Sized to sit optically level with the 13pt-semibold SF Symbol rows.
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 15, height: 15)
        }
    }

    func topLevelRow(
        title: String,
        icon: TopLevelIcon,
        item: SidebarItem,
        bottomSpacing: CGFloat = 0,
        isTopLevelTerminal: Bool = false
    ) -> some View {
        let isSelected = appState.selectedSidebarItem == item

        return HStack(spacing: 8) {
            topLevelIconImage(for: icon)
                .frame(width: topLevelIconColumnWidth, alignment: .center)
                .foregroundColor(topLevelIconColor(isSelected: isSelected))
                .accessibilityHidden(true)

            Text(title)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SidebarRowMetrics.topLevelAndThreadContentHeight, alignment: .center)
            .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding - topIconOpticalInset)
            .appSelectableRow(
                isSelected: isSelected,
                selectionBackgroundBottomInset: bottomSpacing,
                showsHoverBackground: !isSidebarDragInteractionInFlight,
                suppressesPressFeedback: isSidebarDragInteractionInFlight,
                suppressesAction: isSidebarDragInteractionInFlight,
                action: {
                    appState.selectedSidebarItem = item
                    claimSidebarFocus()
                }
            )
            // Measure visible content before the trailing group spacing, so the published bottom
            // edge is where the row actually ends.
            .sidebarDragGeometry(.topLevelTerminal, isEnabled: isTopLevelTerminal)
            .padding(.bottom, bottomSpacing)
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
        if let projectPath = sidebarProjectPathToExpand(
            for: item,
            resolveThread: { uiModelContext.resolveThread(id: $0) }
        ) {
            expandedProjects.insert(projectPath)
        }
    }

    private func topLevelIconColor(isSelected: Bool) -> Color {
        guard !isSelected else {
            return Color(nsColor: sidebarTopLevelSelectedIconNSColor)
        }
        return AppAccentIcon.foreground
    }
}

/// Whichever top-level row ends the group publishes `.topLevelTerminal`, so the empty-`Pinned`
/// drop target knows where the region above `Projects` begins. `Archived` is conditional, so the
/// role moves to `Pull Requests` while it is hidden — the same rule that owns the group's trailing
/// spacing.
func sidebarTopLevelRowIsTerminal(_ item: SidebarItem, hasArchivedThreads: Bool) -> Bool {
    switch item {
    case .archived:
        return hasArchivedThreads
    case .pullRequests:
        return !hasArchivedThreads
    default:
        return false
    }
}

func sidebarDraftMaterializedMode(_ notification: Notification) -> AgentThreadMode {
    (notification.userInfo?[ThreadDraftNotificationKey.mode] as? String)
        .flatMap(AgentThreadMode.init(rawValue:)) ?? .project
}

func sidebarProjectPathToExpandAfterDraftMaterialization(_ notification: Notification) -> String? {
    guard sidebarDraftMaterializedMode(notification) == .project else {
        return nil
    }
    return notification.userInfo?[ThreadDraftNotificationKey.projectPath] as? String
}

@MainActor
func sidebarProjectPathToExpand(
    for item: SidebarItem?,
    resolveThread: (PersistentIdentifier) -> AgentThread?
) -> String? {
    switch item {
    case .project(let project):
        return project.path
    case .thread(let thread):
        guard let resolvedThread = resolveThread(thread.persistentModelID),
              resolvedThread.effectiveMode == .project,
              !resolvedThread.isPinned || resolvedThread.project?.isPinned == true else {
            return nil
        }
        return resolvedThread.project?.path
    case .skills, .mcp, .scheduled, .pullRequests, .archived, .settings, nil:
        return nil
    }
}

private let sidebarTopLevelSelectedIconNSColor = NSColor(name: nil, dynamicProvider: { appearance in
    switch appearance.bestMatch(from: [.darkAqua, .aqua]) {
    case .darkAqua:
        return AppAccentIcon.foregroundNSColor.resolved(for: appearance)
    default:
        return NSColor.labelColor.resolved(for: appearance)
    }
})
