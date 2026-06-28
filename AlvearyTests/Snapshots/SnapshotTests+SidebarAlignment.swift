import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarProjectsHeaderActionAlignsWithProjectRowAction() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")
        let stack = VStack(spacing: 0) {
            SidebarSectionHeaderRow(title: "Projects", onAddProject: {})
            SidebarProjectRow(
                project: project,
                isExpanded: false,
                isSelected: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
            .appSelectionRowBackground(isSelected: true)
        }

        assertMacSnapshot(
            stack,
            size: CGSize(width: 320, height: 92),
            named: "projects_header_project_action_alignment"
        )
    }
}
