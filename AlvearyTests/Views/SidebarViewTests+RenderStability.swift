import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

/// Locks the sidebar rows' `Equatable` contracts: closures are excluded, every rendered value is
/// compared, and a drag configuration compares its `logicalOrder` so a skipped row body cannot
/// keep a gesture whose captured order the list no longer renders.
@MainActor
extension SidebarViewTests {
    func testThreadRowEqualityIgnoresItsActionsAndComparesTheRenderedValues() {
        let thread = AgentThread(name: "Alpha", useWorktree: true)
        let row = makeThreadRow(thread: thread)

        XCTAssertEqual(row, makeThreadRow(thread: thread, onCommitRename: { _ in XCTFail("unused") }))
        XCTAssertEqual(row, makeThreadRow(thread: thread, onConfirmCleanup: { XCTFail("unused") }))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread, status: .busy))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread, isSelected: true))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread, editingThreadID: thread.persistentModelID))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread, cleanupAction: .delete))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread, cleanupDisabledReason: "attached"))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread, suppressHoverAffordances: true))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread, canBeginRename: false))
        XCTAssertNotEqual(row, makeThreadRow(thread: AgentThread(name: "Beta")))
    }

    func testThreadRowEqualityComparesItsDragConfiguration() {
        let thread = AgentThread(name: "Alpha")
        let configuration = makeDragConfiguration()
        let row = makeThreadRow(thread: thread, dragConfiguration: configuration)

        XCTAssertEqual(row, makeThreadRow(thread: thread, dragConfiguration: makeDragConfiguration()))
        XCTAssertNotEqual(row, makeThreadRow(thread: thread))
        XCTAssertNotEqual(
            row,
            makeThreadRow(thread: thread, dragConfiguration: makeDragConfiguration(isEnabled: false))
        )
        XCTAssertNotEqual(
            row,
            makeThreadRow(
                thread: thread,
                dragConfiguration: makeDragConfiguration(sections: [.section(.custom("other"))])
            )
        )
    }

    /// The `logicalOrder` comparison is what keeps an Equatable row's kept gesture honest: two
    /// configurations differing only in captured order must compare unequal.
    func testDragConfigurationEqualityComparesOrderAndIgnoresClosures() {
        let configuration = makeDragConfiguration()

        XCTAssertEqual(
            configuration,
            makeDragConfiguration(onChanged: { _ in XCTFail("unused") }, onEnded: { _ in XCTFail("unused") })
        )
        XCTAssertNotEqual(configuration, makeDragConfiguration(item: .section(.projects)))
        XCTAssertNotEqual(configuration, makeDragConfiguration(isEnabled: false))
        XCTAssertNotEqual(configuration, makeDragConfiguration(sections: [.section(.custom("other"))]))
    }

    func testProjectRowEqualityIgnoresItsActionsAndComparesTheRenderedValues() {
        let row = makeProjectRow()

        XCTAssertEqual(row, makeProjectRow(onActivate: { XCTFail("unused") }))
        XCTAssertNotEqual(row, makeProjectRow(projectName: "Renamed"))
        XCTAssertNotEqual(row, makeProjectRow(isExpanded: true))
        XCTAssertNotEqual(row, makeProjectRow(isSelected: true))
        XCTAssertNotEqual(row, makeProjectRow(suppressHoverAffordances: true))
        XCTAssertNotEqual(row, makeProjectRow(dragConfiguration: makeDragConfiguration()))
    }

    func testSectionHeaderRowEqualityComparesValueHalvesAndActionPresence() {
        let row = makeHeaderRow()

        XCTAssertEqual(row, makeHeaderRow(onAddProject: { XCTFail("unused") }))
        XCTAssertNotEqual(row, makeHeaderRow(title: "Tasks"))
        XCTAssertNotEqual(row, makeHeaderRow(onAddProject: nil))
        XCTAssertNotEqual(row, makeHeaderRow(disclosureExpanded: false))
        XCTAssertNotEqual(row, makeHeaderRow(isEditing: true))
        XCTAssertNotEqual(row, makeHeaderRow(suppressHoverAffordances: true))
    }
}

@MainActor
private func makeThreadRow(
    thread: AgentThread,
    status: ThreadStatus = .stopped,
    isSelected: Bool = false,
    editingThreadID: PersistentIdentifier? = nil,
    cleanupAction: ThreadCleanupAction = .archive,
    cleanupDisabledReason: String? = nil,
    suppressHoverAffordances: Bool = false,
    canBeginRename: Bool = true,
    dragConfiguration: SidebarRowDragConfiguration? = nil,
    onCommitRename: @escaping (String) -> Void = { _ in },
    onConfirmCleanup: @escaping () -> Void = {}
) -> SidebarThreadRow {
    SidebarThreadRow(
        presentation: SidebarThreadRowPresentation(thread: thread),
        status: status,
        isSelected: isSelected,
        editingThreadID: editingThreadID,
        cleanupAction: cleanupAction,
        cleanupDisabledReason: cleanupDisabledReason,
        suppressHoverAffordances: suppressHoverAffordances,
        canBeginRename: canBeginRename,
        dragConfiguration: dragConfiguration,
        onCommitRename: onCommitRename,
        onConfirmCleanup: onConfirmCleanup
    )
}

@MainActor
private func makeProjectRow(
    projectName: String = "Alveary",
    isExpanded: Bool = false,
    isSelected: Bool = false,
    suppressHoverAffordances: Bool = false,
    dragConfiguration: SidebarRowDragConfiguration? = nil,
    onActivate: @escaping () -> Void = {}
) -> SidebarProjectRow {
    SidebarProjectRow(
        projectName: projectName,
        isExpanded: isExpanded,
        isSelected: isSelected,
        suppressHoverAffordances: suppressHoverAffordances,
        dragConfiguration: dragConfiguration,
        onToggleExpanded: {},
        onActivate: onActivate,
        onCreateThread: {}
    )
}

@MainActor
private func makeHeaderRow(
    title: String = "Projects",
    suppressHoverAffordances: Bool = false,
    disclosureExpanded: Bool = true,
    isEditing: Bool = false,
    onAddProject: (@MainActor () -> Void)? = {}
) -> SidebarSectionHeaderRow {
    SidebarSectionHeaderRow(
        title: title,
        disclosure: SidebarSectionHeaderDisclosure(isExpanded: disclosureExpanded, onToggle: {}),
        suppressHoverAffordances: suppressHoverAffordances,
        editing: SidebarSectionHeaderEditing(isEditing: isEditing, onCommit: { _ in }, onCancel: {}),
        onAddProject: onAddProject
    )
}

@MainActor
private func makeDragConfiguration(
    item: SidebarDragItem = .section(.custom("section")),
    isEnabled: Bool = true,
    sections: [SidebarDragItem] = [.section(.custom("section"))],
    onChanged: @escaping @MainActor (CGPoint) -> Void = { _ in },
    onEnded: @escaping @MainActor (CGPoint) -> Void = { _ in }
) -> SidebarRowDragConfiguration {
    SidebarRowDragConfiguration(
        item: item,
        isEnabled: isEnabled,
        logicalOrder: SidebarDragLogicalOrder(
            pinnedItems: [],
            regularProjects: [],
            sections: sections
        ),
        onChanged: onChanged,
        onEnded: onEnded
    )
}
