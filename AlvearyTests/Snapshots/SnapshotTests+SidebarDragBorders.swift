import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarDragTasksSectionRendersContainerBorder() async throws {
        let sidebar = try await makeSidebarSnapshotFixture(includePinnedThread: true)
        let pinnedThread = try XCTUnwrap(sidebar.pinnedThread)

        assertMacSnapshot(
            SidebarDragContainerBorderSnapshot(draggedTask: pinnedThread, project: sidebar.project),
            size: CGSize(width: 320, height: 260),
            named: "sidebar_drag_tasks_container_border"
        )
    }

    /// The reported bug: a selected project row's accent fill traced almost the same rectangle as
    /// the drop border, so the two read as one misaligned outline.
    func testSidebarDragBorderClearsASelectedProjectRow() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        assertMacSnapshot(
            SidebarDragSelectedProjectBorderSnapshot(project: sidebar.project),
            size: CGSize(width: 320, height: 140),
            named: "sidebar_drag_border_over_selected_project"
        )
    }

    func testSidebarTaskProjectAccessConfirmationText() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        assertMacSnapshot(
            SidebarTaskAccessDialogTextSnapshot(
                projectName: sidebar.project.name,
                placeholderID: sidebar.project.persistentModelID
            ),
            size: CGSize(width: 300, height: 190),
            named: "sidebar_task_access_confirmation_text"
        )
    }
}

/// Renders the confirmation copy exactly as the dialog composes it. A regression here previously
/// dumped each nested `Text`'s debug description into the message.
@MainActor
private struct SidebarTaskAccessDialogTextSnapshot: View {
    let projectName: String
    let placeholderID: PersistentIdentifier

    var body: some View {
        sidebarTaskProjectAccessConfirmationText(
            for: SidebarTaskProjectAccessRequest(
                threadID: placeholderID,
                projectID: placeholderID,
                threadName: "New task",
                projectName: projectName,
                projectKey: "project-id",
                restartsAgentProcess: true,
                grantsNewAccess: true
            )
        )
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
    }
}

@MainActor
private struct SidebarDragSelectedProjectBorderSnapshot: View {
    let project: Project

    /// The project row's 24pt content rect, matching what `.projectHeader` publishes.
    private let groupFrame = CGRect(x: 0, y: 61, width: 320, height: 24)

    var body: some View {
        List {
            SidebarSectionHeaderRow(title: "Projects", onAddProject: {})
            SidebarProjectRow(
                projectName: project.name,
                isExpanded: false,
                isSelected: true,
                suppressHoverAffordances: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
            .appSelectionRowBackground(isSelected: true)
        }
        .listStyle(.sidebar)
        .overlay {
            GeometryReader { proxy in
                SidebarSectionContainerBorder(
                    frame: groupFrame.insetBy(dx: 0, dy: -SidebarDropTargetingMetrics.containerOutset),
                    viewport: CGRect(origin: .zero, size: proxy.size),
                    overlaySize: proxy.size
                )
            }
        }
    }
}

/// Renders the production container overlay using deterministic drag geometry.
@MainActor
private struct SidebarDragContainerBorderSnapshot: View {
    let draggedTask: AgentThread
    let project: Project

    /// Spans the Tasks header down through the placeholder row, matching the union of
    /// `.tasksHeader` and `.tasksTerminal` that production feeds the overlay.
    private let tasksSectionFrame = CGRect(x: 0, y: 196, width: 320, height: 56)

    var body: some View {
        List {
            SidebarSectionHeaderRow(title: "Pinned")

            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: draggedTask),
                status: .waitingForUser,
                isSelected: false,
                layout: .topLevel,
                suppressHoverAffordances: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding)
            .opacity(0.48)

            SidebarSectionHeaderRow(title: "Projects", showsTopDivider: true, onAddProject: {})
            SidebarProjectRow(
                projectName: project.name,
                isExpanded: false,
                isSelected: false,
                suppressHoverAffordances: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )

            SidebarSectionHeaderRow(
                title: "Tasks",
                showsTopDivider: true,
                actionSystemImage: "plus",
                actionAccessibilityLabel: "New task",
                actionHelp: "New task",
                onAction: {}
            )

            // The dragged pinned task still exists, so production shows the tasks-elsewhere label.
            Text("No tasks here")
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
        }
        .listStyle(.sidebar)
        .overlay {
            GeometryReader { proxy in
                SidebarSectionContainerBorder(
                    frame: tasksSectionFrame,
                    viewport: CGRect(origin: .zero, size: proxy.size),
                    overlaySize: proxy.size
                )
            }
        }
    }
}
