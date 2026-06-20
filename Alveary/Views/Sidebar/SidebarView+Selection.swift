import AppKit
import SwiftUI

// SF Symbols include leading side bearings; compensate so visible icon ink aligns with the header text.
private let topIconOpticalInset: CGFloat = 4

enum SidebarRowMetrics {
    private static let labelHeight: CGFloat = 16

    static let topLevelAndThreadVerticalPadding: CGFloat = 4
    static let topLevelAndThreadContentHeight: CGFloat = labelHeight + topLevelAndThreadVerticalPadding * 2
    static let topLevelRowSpacing: CGFloat = 4
    static let interThreadRowSpacing: CGFloat = 2
}

extension SidebarView {
    func activeThreads(for project: Project) -> [AgentThread] {
        viewModel.activeThreads(for: project)
    }

    func topLevelRow(
        title: String,
        systemImage: String,
        item: SidebarItem,
        bottomSpacing: CGFloat = 0
    ) -> some View {
        let isSelected = appState.selectedSidebarItem == item

        return HStack(spacing: 8) {
            Image(systemName: systemImage)
                .symbolRenderingMode(.monochrome)
                .renderingMode(.template)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(topLevelIconColor(isSelected: isSelected))
                .accessibilityHidden(true)

            Text(title)
        }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: SidebarRowMetrics.topLevelAndThreadContentHeight, alignment: .center)
            .padding(.leading, SidebarProjectsHeaderRow.contentLeadingPadding - topIconOpticalInset)
            .appSelectableRow(
                isSelected: isSelected,
                selectionBackgroundBottomInset: bottomSpacing,
                action: {
                    appState.selectedSidebarItem = item
                    claimSidebarFocus()
                }
            )
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

    private func topLevelIconColor(isSelected: Bool) -> Color {
        guard !isSelected else {
            return Color(nsColor: sidebarTopLevelSelectedIconNSColor)
        }
        return AppAccentIcon.foreground
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
