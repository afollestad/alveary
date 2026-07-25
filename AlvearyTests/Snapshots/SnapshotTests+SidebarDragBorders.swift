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
}

/// Mirrors what `sidebarDragOverlay` draws for a `.container` candidate: the border is an overlay
/// on the list, positioned from drag geometry, so the snapshot feeds it a synthetic frame instead
/// of driving a live drag.
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
                thread: draggedTask,
                status: .waitingForUser,
                isSelected: false,
                layout: .topLevel,
                editingThreadID: .constant(nil),
                suppressHoverAffordances: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding)
            .opacity(0.48)

            SidebarSectionHeaderRow(title: "Projects", showsTopDivider: true, onAddProject: {})
            SidebarProjectRow(
                project: project,
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

            Text("No tasks")
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
        }
        .listStyle(.sidebar)
        .overlay {
            GeometryReader { proxy in
                let rect = sidebarDragBorderLocalRect(
                    frame: tasksSectionFrame,
                    viewport: CGRect(origin: .zero, size: proxy.size),
                    overlaySize: proxy.size
                )
                RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                    .fill(Color.accentColor.opacity(SidebarDragBorderMetrics.fillOpacity))
                    .overlay {
                        RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
                            .strokeBorder(
                                Color.accentColor.opacity(SidebarDragBorderMetrics.strokeOpacity),
                                lineWidth: SidebarDragBorderMetrics.lineWidth
                            )
                    }
                    .frame(width: rect.width, height: rect.height)
                    .offset(x: rect.minX, y: rect.minY)
                    .allowsHitTesting(false)
            }
        }
    }
}
