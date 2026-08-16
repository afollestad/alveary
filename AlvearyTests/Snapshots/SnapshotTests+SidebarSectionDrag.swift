import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    /// A custom section takes the same whole-section border `Tasks` and `Pinned` show a source
    /// that is choosing membership rather than position.
    func testSidebarDragCustomSectionRendersContainerBorder() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture(memberNames: ["Review release notes"])
        let member = try XCTUnwrap(sidebar.members.first)

        assertMacSnapshot(
            SidebarCustomSectionDragBorderSnapshot(draggedTask: member),
            size: CGSize(width: 320, height: 260),
            named: "sidebar_drag_custom_section_border"
        )
    }

    /// A section reorder draws an insertion line between sections, never a container border —
    /// a section lands between its siblings, never inside one.
    func testSidebarDragSectionReorderRendersInsertionLine() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture(memberNames: ["Review release notes"])
        let member = try XCTUnwrap(sidebar.members.first)

        assertMacSnapshot(
            SidebarSectionReorderLineSnapshot(draggedSectionMember: member),
            size: CGSize(width: 320, height: 260),
            named: "sidebar_drag_section_reorder_line"
        )
    }
}

/// The custom-section container border, drawn from the union of `.customSectionHeader` and
/// `.customSectionTerminal` exactly as production feeds the overlay.
private struct SidebarCustomSectionDragBorderSnapshot: View {
    let draggedTask: AgentThread

    private let sectionFrame = CGRect(x: 0, y: 110, width: 320, height: 84)

    var body: some View {
        List {
            SidebarSectionHeaderRow(
                title: "Tasks",
                showsTopDivider: true,
                actionSystemImage: "plus",
                actionAccessibilityLabel: "New task",
                actionHelp: "New task",
                onAction: {}
            )

            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: draggedTask),
                status: .stopped,
                isSelected: false,
                layout: .topLevel,
                suppressHoverAffordances: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding)
            .opacity(0.48)

            SidebarSectionHeaderRow(title: "Research", showsTopDivider: true)

            Text(sidebarCustomSectionPlaceholderLabel())
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)
        }
        .listStyle(.sidebar)
        .overlay {
            GeometryReader { proxy in
                sidebarSnapshotSectionContainerBorder(
                    frame: sectionFrame,
                    viewport: CGRect(origin: .zero, size: proxy.size),
                    overlaySize: proxy.size
                )
            }
        }
    }
}

/// The section-reorder affordance: a 2pt line on the boundary the dragged section would land on,
/// with the dragged section's header and rows faded like any other dragged group.
private struct SidebarSectionReorderLineSnapshot: View {
    let draggedSectionMember: AgentThread

    private let boundaryY: CGFloat = 110

    var body: some View {
        List {
            SidebarSectionHeaderRow(title: "Projects", showsTopDivider: true, onAddProject: {})

            Text("No projects yet")
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)

            SidebarSectionHeaderRow(title: "Research", showsTopDivider: true)
                .opacity(0.48)

            SidebarThreadRow(
                presentation: SidebarThreadRowPresentation(thread: draggedSectionMember),
                status: .stopped,
                isSelected: false,
                layout: .topLevel,
                suppressHoverAffordances: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding)
            .opacity(0.48)
        }
        .listStyle(.sidebar)
        .overlay {
            GeometryReader { proxy in
                Rectangle()
                    .fill(Color.accentColor)
                    .frame(width: proxy.size.width, height: 2)
                    .offset(y: boundaryY)
                    .allowsHitTesting(false)
            }
        }
    }
}

/// The whole-section outline production draws from `sidebarSectionContainerBorder`, shared here by
/// the drop-container baselines and the secondary-click highlight one.
@MainActor
func sidebarSnapshotSectionContainerBorder(
    frame: CGRect,
    viewport: CGRect,
    overlaySize: CGSize
) -> some View {
    let rect = sidebarDragBorderLocalRect(frame: frame, viewport: viewport, overlaySize: overlaySize)
    return RoundedRectangle(cornerRadius: AppCornerRadius.standard, style: .continuous)
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
