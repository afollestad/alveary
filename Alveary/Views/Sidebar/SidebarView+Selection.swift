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
        // Both conditional rows can be absent, so the row that ends the group — which owns the
        // trailing spacing and the `.topLevelTerminal` drag role — comes from the visible list
        // rather than from either row's own condition.
        let terminalItem = sidebarTopLevelRowItems(
            showsPullRequests: context.showsPullRequests,
            hasArchivedThreads: context.hasArchivedThreads
        ).last
        topLevelRow(
            title: "Skills",
            icon: .system("puzzlepiece.extension"),
            item: .skills,
            bottomSpacing: topLevelRowBottomSpacing(.skills, terminalItem: terminalItem),
            isTopLevelTerminal: terminalItem == .skills
        )
        topLevelRow(
            title: "MCP",
            icon: .system("server.rack"),
            item: .mcp,
            bottomSpacing: topLevelRowBottomSpacing(.mcp, terminalItem: terminalItem),
            isTopLevelTerminal: terminalItem == .mcp
        )
        topLevelRow(
            title: "Scheduled",
            icon: .system("clock"),
            item: .scheduled,
            bottomSpacing: topLevelRowBottomSpacing(.scheduled, terminalItem: terminalItem),
            isTopLevelTerminal: terminalItem == .scheduled
        )
        if context.showsPullRequests {
            topLevelRow(
                title: "Pull requests",
                icon: .asset("PullRequestOcticon"),
                item: .pullRequests,
                bottomSpacing: topLevelRowBottomSpacing(.pullRequests, terminalItem: terminalItem),
                isTopLevelTerminal: terminalItem == .pullRequests
            )
        }
        if context.hasArchivedThreads {
            topLevelRow(
                title: "Archived",
                icon: .system("archivebox"),
                item: .archived,
                bottomSpacing: topLevelRowBottomSpacing(.archived, terminalItem: terminalItem),
                isTopLevelTerminal: terminalItem == .archived
            )
        }
    }

    /// Whichever row ends the group takes no bottom spacing; the Projects/Pinned header
    /// below owns that boundary.
    private func topLevelRowBottomSpacing(_ item: SidebarItem, terminalItem: SidebarItem?) -> CGFloat {
        terminalItem == item ? 0 : SidebarRowMetrics.topLevelRowSpacing
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
            // Selection alone no longer expands (see `sidebarProjectPathToExpand`), so activating
            // a project row reveals its children here — clicking one is a request to see inside it.
            expandedProjects.insert(project.path)
        }
        claimSidebarFocus()
    }

    func activateThread(_ thread: AgentThread) {
        appState.selectedSidebarItem = .thread(thread)
        claimSidebarFocus()
    }

    /// Hiding the row removes the only way back to the Pull Requests screen, so any selection or
    /// preserved Settings bookmark pointing at it has to go with it. The toggle lives in Settings,
    /// so in practice it is the bookmark that would otherwise restore a rowless screen on dismiss.
    func handlePullRequestsVisibilityChange(showsPullRequests: Bool) {
        guard !showsPullRequests else {
            return
        }
        if appState.selectedSidebarItem == .pullRequests {
            appState.selectedSidebarItem = nil
        }
        if appState.previousSelection == .pullRequests {
            appState.previousSelection = nil
        }
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

/// The top-level rows that actually render, in order. `Pull Requests` is user-hideable and
/// `Archived` appears only with archived threads, so the group's trailing spacing and its
/// `.topLevelTerminal` role both follow this list's last element rather than either row's own
/// condition — with both conditional rows hidden that is `Scheduled`. The empty-`Pinned` drop
/// target aims at whichever row publishes the role, so this must stay the only definition of it.
func sidebarTopLevelRowItems(showsPullRequests: Bool, hasArchivedThreads: Bool) -> [SidebarItem] {
    var items: [SidebarItem] = [.skills, .mcp, .scheduled]
    if showsPullRequests {
        items.append(.pullRequests)
    }
    if hasArchivedThreads {
        items.append(.archived)
    }
    return items
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

/// The project a selection must reveal, or nil when the selection implies no expansion.
///
/// Selecting a project row deliberately does not expand it: keyboard traversal has to be able
/// to rest on a collapsed row, or the left-arrow collapse is undone the moment the selection
/// moves back onto that project. Sites that mean "reveal" — row activation, draft flows,
/// pin/unpin, the drop finalizer — expand explicitly instead.
@MainActor
func sidebarProjectPathToExpand(
    for item: SidebarItem?,
    resolveThread: (PersistentIdentifier) -> AgentThread?
) -> String? {
    switch item {
    case .thread(let thread):
        guard let resolvedThread = resolveThread(thread.persistentModelID),
              resolvedThread.effectiveMode == .project,
              !resolvedThread.isPinned || resolvedThread.project?.isPinned == true else {
            return nil
        }
        return resolvedThread.project?.path
    case .project, .skills, .mcp, .scheduled, .pullRequests, .archived, .settings, nil:
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
