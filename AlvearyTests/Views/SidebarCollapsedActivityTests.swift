import Foundation
import XCTest

@testable import Alveary

@MainActor
final class SidebarCollapsedActivityTests: XCTestCase {
    // MARK: - Sections

    func testCollapsedTasksSectionHidingAWaitingTaskIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let waiting = insertTask(name: "Waiting", in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.tasks], waiting: [waiting])

        XCTAssertEqual(activity.hiddenActivity(inSection: .tasks), .waitingForUser)
    }

    // The row shows its own dot while the section is open, so the header must not double it.
    func testExpandedTasksSectionIsNeverFlagged() throws {
        let fixture = try SidebarTestFixture()
        let waiting = insertTask(name: "Waiting", in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [], waiting: [waiting])

        XCTAssertEqual(activity, .none)
    }

    func testCollapsedTasksSectionWithNothingWaitingIsNotFlagged() throws {
        let fixture = try SidebarTestFixture()
        _ = insertTask(name: "Idle", in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.tasks], waiting: [])

        XCTAssertEqual(activity, .none)
    }

    func testCollapsedCustomSectionHidingAWaitingMemberIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try makeCustomSection(named: "Research", in: fixture)
        let member = insertTask(name: "Member", in: fixture)
        member.customSection = fixture.context.resolveSidebarSection(id: sectionID)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.custom(sectionID)], waiting: [member])

        XCTAssertEqual(activity.hiddenActivity(inSection: .custom(sectionID)), .waitingForUser)
        // Its home section absorbed it, so `Tasks` never listed it in the first place.
        XCTAssertNil(activity.hiddenActivity(inSection: .tasks))
    }

    // A pinned member renders under `Pinned`, which never collapses, so the collapse hides nothing.
    func testPinnedCustomSectionMemberDoesNotFlagItsCollapsedSection() throws {
        let fixture = try SidebarTestFixture()
        let sectionID = try makeCustomSection(named: "Research", in: fixture)
        let member = insertTask(name: "Pinned member", isPinned: true, in: fixture)
        member.pinnedSortOrder = 0
        member.customSection = fixture.context.resolveSidebarSection(id: sectionID)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.custom(sectionID)], waiting: [member])

        XCTAssertEqual(activity, .none)
    }

    func testCollapsedProjectsSectionAggregatesEveryProjectChild() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-projects")
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let activity = try fold(
            fixture,
            collapsedSections: [.projects],
            expandedProjects: [project.path],
            waiting: [child]
        )

        XCTAssertEqual(activity.hiddenActivity(inSection: .projects), .waitingForUser)
    }

    // `Pinned` heads a group with no collapse of its own, so it can never carry the dot.
    func testPinnedSectionIsNeverFlagged() throws {
        let fixture = try SidebarTestFixture()
        let pinned = insertTask(name: "Pinned", isPinned: true, in: fixture)
        pinned.pinnedSortOrder = 0
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.tasks], waiting: [pinned])

        XCTAssertNil(activity.hiddenActivity(inSection: .pinned))
        XCTAssertEqual(activity, .none)
    }

    // MARK: - Project rows

    func testCollapsedProjectRowHidingAWaitingChildIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-collapsed")
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [], waiting: [child])

        XCTAssertEqual(activity.hiddenActivity(inProjectAt: project.path), .waitingForUser)
        // The section is open, so only the row it hid carries the dot.
        XCTAssertNil(activity.hiddenActivity(inSection: .projects))
    }

    func testExpandedProjectRowIsNeverFlagged() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-expanded")
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let activity = try fold(
            fixture,
            collapsedSections: [],
            expandedProjects: [project.path],
            waiting: [child]
        )

        XCTAssertEqual(activity, .none)
    }

    // `Pinned` does not collapse, but the project rows inside it do.
    func testCollapsedPinnedProjectRowIsFlagged() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/waiting-pinned-project")
        project.isPinned = true
        project.pinnedSortOrder = 0
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [], waiting: [child])

        XCTAssertEqual(activity.hiddenActivity(inProjectAt: project.path), .waitingForUser)
    }

    // MARK: - Working

    func testCollapsedTasksSectionHidingABusyTaskReportsWorking() throws {
        let fixture = try SidebarTestFixture()
        let busy = insertTask(name: "Busy", in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.tasks], working: [busy])

        XCTAssertEqual(activity.hiddenActivity(inSection: .tasks), .working)
    }

    func testCollapsedProjectRowHidingABusyChildReportsWorking() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alpha", path: "/tmp/working-collapsed")
        let child = insertProjectThread(name: "Child", project: project, in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [], working: [child])

        XCTAssertEqual(activity.hiddenActivity(inProjectAt: project.path), .working)
    }

    // Deliberately inverts `ThreadStatus.folded`, where `.busy` outranks `.waitingForUser` for a
    // single thread. Across separate hidden threads the answer is the only one the user can act on.
    func testWaitingOutranksWorkingAcrossHiddenThreads() throws {
        let fixture = try SidebarTestFixture()
        let busy = insertTask(name: "Busy", in: fixture)
        let waiting = insertTask(name: "Waiting", in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.tasks], waiting: [waiting], working: [busy])

        XCTAssertEqual(activity.hiddenActivity(inSection: .tasks), .waitingForUser)
    }

    // An inert thread is not worth standing in for: nothing to act on, nothing to wait for.
    func testCollapsedSectionHidingOnlyInertThreadsReportsNothing() throws {
        let fixture = try SidebarTestFixture()
        _ = insertTask(name: "Idle", in: fixture)
        try fixture.context.save()

        let activity = try fold(fixture, collapsedSections: [.tasks])

        XCTAssertEqual(activity, .none)
    }

    // MARK: - Accessibility

    // Both rows hide the dot from VoiceOver and announce it through this label instead, so the
    // wording is the only thing a screen-reader user gets.
    func testAccessibilityLabelNamesWhicheverActivityTheIndicatorShows() {
        XCTAssertEqual(
            sidebarHiddenActivityAccessibilityLabel("Expand Tasks", activity: .waitingForUser),
            "Expand Tasks, waiting for you"
        )
        XCTAssertEqual(
            sidebarHiddenActivityAccessibilityLabel("Expand Tasks", activity: .working),
            "Expand Tasks, working"
        )
        XCTAssertEqual(
            sidebarHiddenActivityAccessibilityLabel("Expand Tasks", activity: nil),
            "Expand Tasks"
        )
    }

    // MARK: - Support

    /// Runs the production fold with each thread's status stated outright, so these cases stay
    /// about which container hides what rather than about how a thread reaches a status.
    private func fold(
        _ fixture: SidebarTestFixture,
        collapsedSections: Set<SidebarCollapsibleSection>,
        expandedProjects: Set<String> = [],
        waiting: [AgentThread] = [],
        working: [AgentThread] = []
    ) throws -> SidebarCollapsedActivity {
        let waitingIDs = Set(waiting.map(\.persistentModelID))
        let workingIDs = Set(working.map(\.persistentModelID))
        return sidebarCollapsedActivity(
            snapshot: try fixture.renderSnapshot(),
            collapsedSections: collapsedSections,
            expandedProjects: expandedProjects,
            statusFor: { thread in
                if waitingIDs.contains(thread.persistentModelID) { return .waitingForUser }
                if workingIDs.contains(thread.persistentModelID) { return .busy }
                return .stopped
            }
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
            throw SidebarCollapsedActivityTestError.sectionNotCreated
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

private enum SidebarCollapsedActivityTestError: Error {
    case sectionNotCreated
}
