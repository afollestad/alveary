import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTasksViewModelTests {
    func testSectionOptionsListCustomSectionsInSidebarOrderExcludingBuiltins() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.context.insert(SidebarSection(id: "pinned-row", kind: .pinned, name: "Pinned", sortOrder: 0))
        fixture.context.insert(SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 4))
        fixture.context.insert(SidebarSection(id: "audits", kind: .custom, name: "Audits", sortOrder: 3))
        try fixture.context.save()

        fixture.viewModel.reload()

        XCTAssertEqual(fixture.viewModel.sectionOptions.map(\.id), ["audits", "reports"])
    }

    func testSectionOptionsReloadWhenSectionsChangeNotificationFires() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        fixture.viewModel.reload()
        XCTAssertTrue(fixture.viewModel.sectionOptions.isEmpty)

        // The sidebar sees section changes through its own `@Query`; an open editor only learns
        // about them through the service's notification.
        let sectionService = SidebarSectionService(
            modelContext: fixture.context,
            notificationCenter: fixture.notificationCenter
        )
        _ = try sectionService.createSection(name: "Reports")

        let deadline = Date().addingTimeInterval(2)
        while fixture.viewModel.sectionOptions.isEmpty, Date() < deadline {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        XCTAssertEqual(fixture.viewModel.sectionOptions.map(\.name), ["Reports"])
    }

    func testSaveResolvesTheSectionAndRejectsAVanishedOne() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        fixture.context.insert(section)
        try fixture.context.save()
        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Sectioned"
        draft.prompt = "Do the work."
        draft.sectionID = "reports"

        XCTAssertTrue(fixture.viewModel.save(draft))
        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertEqual(definition.destination, .reusedThread)
        XCTAssertEqual(definition.threadSection?.id, "reports")

        var staleDraft = fixture.viewModel.makeNewDraft()
        staleDraft.title = "Stale"
        staleDraft.prompt = "Do the work."
        staleDraft.sectionID = "vanished"
        XCTAssertFalse(fixture.viewModel.save(staleDraft))
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ScheduledTask>()), 1)
    }

    func testEditDraftRestoresTheSectionAndProjectBackedDraftsDropIt() throws {
        let fixture = try ScheduledTasksViewModelFixture()
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        fixture.context.insert(section)
        try fixture.context.save()
        var draft = fixture.viewModel.makeNewDraft()
        draft.title = "Sectioned"
        draft.prompt = "Do the work."
        draft.sectionID = "reports"
        XCTAssertTrue(fixture.viewModel.save(draft))
        let definition = try XCTUnwrap(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).first)

        let editDraft = try XCTUnwrap(fixture.viewModel.makeEditDraft(definitionID: definition.id))
        XCTAssertEqual(editDraft.sectionID, "reports")

        // A hidden stale pick must not survive a Project selection at save time.
        let project = Project(path: "/tmp/section-project", name: "Sectioned Project")
        fixture.context.insert(project)
        try fixture.context.save()
        var projectDraft = editDraft
        projectDraft.workspaceKind = .project
        projectDraft.projectPath = project.path
        XCTAssertTrue(fixture.viewModel.save(projectDraft))
        XCTAssertNil(definition.threadSection)
    }
}
