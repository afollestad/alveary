import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarProjectRowSelectedHoverShowsNewThreadButton() {
        let project = Project(path: "/tmp/alveary", name: "Alveary")

        assertMacSnapshot(
            SidebarProjectRow(
                project: project,
                isExpanded: false,
                isSelected: true,
                initialRowHover: true,
                onToggleExpanded: {},
                onActivate: {},
                onCreateThread: {}
            )
            .appSelectionRowBackground(isSelected: true),
            size: CGSize(width: 280, height: 52),
            named: "project_row_selected_hover_new_thread"
        )
    }
}
