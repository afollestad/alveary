import Foundation
import XCTest

@testable import Alveary

@MainActor
final class SidebarWaitingAttentionTests: XCTestCase {
    // MARK: - Sections

    func testCollapsedTasksSectionHidingAWaitingTaskIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let waiting = insertTask(name: "Waiting", in: fixture)
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [.tasks], waiting: [waiting])

        XCTAssertTrue(attention.hidesWaitingThread(inSection: .tasks))
    }

    // The row shows its own dot while the section is open, so the header must not double it.
    func testExpandedTasksSectionIsNeverFlagged() throws {
        let fixture = try SidebarTestFixture()
        let waiting = insertTask(name: "Waiting", in: fixture)
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [], waiting: [waiting])

        XCTAssertEqual(attention, .none)
    }

    func testCollapsedTasksSectionWithNothingWaitingIsNotFlagged() throws {
        let fixture = try SidebarTestFixture()
        _ = insertTask(name: "Idle", in: fixture)
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [.tasks], waiting: [])

        XCTAssertEqual(attention, .none)
    }

    func testCollapsedCustomSectionHidingAWaitingMemberIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try makeCustomSection(named: "Research", in: fixture)
        let member = insertTask(name: "Member", in: fixture)
        member.customSection = fixture.context.resolveSidebarSection(id: sectionID)
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [.custom(sectionID)], waiting: [member])

        XCTAssertTrue(attention.hidesWaitingThread(inSection: .custom(sectionID)))
        // Its home section absorbed it, so `Tasks` never listed it in the first place.
        XCTAssertFalse(attention.hidesWaitingThread(inSection: .tasks))
    }

    // A pinned member renders under `Pinned`, which never collapses, so the collapse hides nothing.
    func testPinnedCustomSectionMemberDoesNotFlagItsCollapsedSection() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try makeCustomSection(named: "Research", in: fixture)
        let member = insertTask(name: "Pinned member", isPinned: true, in: fixture)
        member.pinnedSortOrder = 0
        member.customSection = fixture.context.resolveSidebarSection(id: sectionID)
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [.custom(sectionID)], waiting: [member])

        XCTAssertEqual(attention, .none)
    }

    func testCollapsedProjectsSectionAggregatesEveryProjectChild() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-projects")
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let attention = try fold(
            fixture,
            collapsedSections: [.projects],
            expandedProjects: [project.path],
            waiting: [child]
        )

        XCTAssertTrue(attention.hidesWaitingThread(inSection: .projects))
    }

    // `Pinned` heads a group with no collapse of its own, so it can never carry the dot.
    func testPinnedSectionIsNeverFlagged() throws {
        let fixture = try SidebarTestFixture()
        let pinned = insertTask(name: "Pinned", isPinned: true, in: fixture)
        pinned.pinnedSortOrder = 0
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [.tasks], waiting: [pinned])

        XCTAssertFalse(attention.hidesWaitingThread(inSection: .pinned))
        XCTAssertEqual(attention, .none)
    }

    // MARK: - Project rows

    func testCollapsedProjectRowHidingAWaitingChildIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-collapsed")
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [], waiting: [child])

        XCTAssertTrue(attention.hidesWaitingThread(inProjectAt: project.path))
        // The section is open, so only the row it hid carries the dot.
        XCTAssertFalse(attention.hidesWaitingThread(inSection: .projects))
    }

    func testExpandedProjectRowIsNeverFlagged() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-expanded")
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let attention = try fold(
            fixture,
            collapsedSections: [],
            expandedProjects: [project.path],
            waiting: [child]
        )

        XCTAssertEqual(attention, .none)
    }

    // `Pinned` does not collapse, but the project rows inside it do.
    func testCollapsedPinnedProjectRowIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-pinned-project")
        project.isPinned = true
        project.pinnedSortOrder = 0
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let attention = try fold(fixture, collapsedSections: [], waiting: [child])

        XCTAssertTrue(attention.hidesWaitingThread(inProjectAt: project.path))
    }

    // MARK: - Accessibility

    // Both rows hide the dot from VoiceOver and announce it through this label instead, so the
    // wording is the only thing a screen-reader user gets.
    func testAccessibilityLabelAnnouncesTheWaitingThreadOnlyWhenTheDotShows() {
        XCTAssertEqual(
            sidebarWaitingAttentionAccessibilityLabel("Expand Tasks", hidesWaitingThread: true),
            "Expand Tasks, waiting for you"
        )
        XCTAssertEqual(
            sidebarWaitingAttentionAccessibilityLabel("Expand Tasks", hidesWaitingThread: false),
            "Expand Tasks"
        )
    }

    // MARK: - Support

    /// Runs the production fold with the waiting set stated outright, so these cases stay about
    /// which container hides what rather than about how a thread reaches `.waitingForUser`.
    private func fold(
        _ fixture: SidebarTestFixture,
        collapsedSections: Set<SidebarCollapsibleSection>,
        expandedProjects: Set<String> = [],
        waiting: [AgentThread]
    ) throws -> SidebarWaitingAttention {
        let waitingIDs = Set(waiting.map(\.persistentModelID))
        return sidebarWaitingAttention(
            snapshot: try fixture.renderSnapshot(),
            collapsedSections: collapsedSections,
            expandedProjects: expandedProjects,
            isWaitingForUser: { waitingIDs.contains($0.persistentModelID) }
        )
    }

    private func makeCustomSection(
        named name: String,
        in fixture: SidebarTestFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        let service = SidebarSectionService(modelContext: fixture.context)
        guard case .created(let section) = try service.createSection(name: name),
              case .custom(let id) = section.id else {
            XCTFail("Expected a created custom section", file: file, line: line)
            throw SidebarWaitingAttentionTestError.sectionNotCreated
        }
        return id
    }

    private func insertTask(
        name: String,
        isPinned: Bool = false,
        in fixture: SidebarTestFixture
    ) -> AgentThread {
        let task = AgentThread(
            name: name,
            isPinned: isPinned,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/\(UUID().uuidString)",
                ownershipStrategy: .projectLocal
            )
        )
        fixture.context.insert(task)
        return task
    }

    private func insertProjectThread(
        name: String,
        project: Project,
        in fixture: SidebarTestFixture
    ) -> AgentThread {
        let thread = AgentThread(name: name, project: project)
        fixture.context.insert(thread)
        return thread
    }
}

private enum SidebarWaitingAttentionTestError: Error {
    case sectionNotCreated
}
