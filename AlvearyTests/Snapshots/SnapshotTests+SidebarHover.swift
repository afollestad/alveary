import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarRowHoverBackgroundSeparateFromSelection() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")
        let thread = AgentThread(name: "Hovered thread")
        let selectedThread = AgentThread(name: "Selected thread")
        let stack = VStack(spacing: SidebarRowMetrics.interThreadRowSpacing) {
            SidebarProjectRow(
                project: project,
                isExpanded: false,
                isSelected: false,
                initialRowHover: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
            .background(sidebarHoverBackground(isSelected: false, isHovered: true))

            SidebarThreadRow(
                thread: thread,
                status: .stopped,
                isSelected: false,
                editingThreadID: .constant(nil),
                cleanupAction: .archive,
                initialRowHover: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(sidebarHoverBackground(isSelected: false, isHovered: true))

            SidebarThreadRow(
                thread: selectedThread,
                status: .stopped,
                isSelected: true,
                editingThreadID: .constant(nil),
                cleanupAction: .archive,
                initialRowHover: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, 14)
            .background(sidebarHoverBackground(isSelected: true, isHovered: true))
        }

        assertMacSnapshot(
            stack,
            size: CGSize(width: 320, height: 108),
            named: "sidebar_row_hover_background",
            colorScheme: .dark
        )
    }
}

private func sidebarHoverBackground(isSelected: Bool, isHovered: Bool) -> some View {
    AppSelectionRowBackground(
        isSelected: isSelected,
        isPressed: false,
        isHovered: isHovered,
        leadingInset: 10,
        trailingInset: 10,
        topInset: 0,
        bottomInset: 0
    )
}
