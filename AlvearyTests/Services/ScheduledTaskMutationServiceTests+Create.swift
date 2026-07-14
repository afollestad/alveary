import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskMutationServiceTests {
    func testCreatePersistsDefinitionWithComputedNextOccurrenceAndPublishesChange() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let actionDate = Date(timeIntervalSince1970: 600)
        let changeExpectation = expectation(description: "scheduled task change published")
        let observer = fixture.notificationCenter.addObserver(
            forName: .scheduledTasksChanged,
            object: nil,
            queue: nil
        ) { notification in
            if notification.userInfo?["definitionID"] is String {
                changeExpectation.fulfill()
            }
        }
        defer { fixture.notificationCenter.removeObserver(observer) }

        let definition = try fixture.service.create(
            edit: ScheduledTaskDefinitionEdit(
                title: "  Morning status  ",
                prompt: "  Summarize changes  ",
                recurrence: .interval(minutes: 5, anchor: Date(timeIntervalSince1970: 0)),
                timeZoneIdentifier: "UTC",
                providerID: "codex",
                model: "gpt-5",
                effort: "high",
                permissionMode: "default",
                workspaceKind: .privateWorkspace,
                workspaceStrategy: .worktree,
                grantedRoots: [CanonicalPath.normalize("/tmp/grant")],
                project: nil
            ),
            at: actionDate
        )

        XCTAssertEqual(definition.title, "Morning status")
        XCTAssertEqual(definition.prompt, "Summarize changes")
        XCTAssertEqual(definition.nextOccurrenceAt, Date(timeIntervalSince1970: 900))
        XCTAssertEqual(definition.state, .active)
        XCTAssertEqual(definition.grantedRoots, ["/tmp/grant"])
        XCTAssertEqual(definition.createdAt, actionDate)
        wait(for: [changeExpectation], timeout: 1)
        XCTAssertEqual(fixture.context.resolveScheduledTask(id: definition.id)?.id, definition.id)
    }

    func testCreateRejectsProjectWorkspaceWithoutProject() throws {
        let fixture = try ScheduledTaskMutationFixture()

        XCTAssertThrowsError(
            try fixture.service.create(
                edit: ScheduledTaskDefinitionEdit(
                    title: "Project task",
                    prompt: "Run checks",
                    recurrence: .daily(hour: 8, minute: 0),
                    timeZoneIdentifier: "UTC",
                    providerID: "codex",
                    model: nil,
                    effort: "medium",
                    permissionMode: "default",
                    workspaceKind: .project,
                    workspaceStrategy: .worktree,
                    grantedRoots: [],
                    project: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskMutationError, .projectWorkspaceRequiresProject)
        }
    }

    func testCreateRejectsNoncanonicalGrantRoots() throws {
        let fixture = try ScheduledTaskMutationFixture()

        XCTAssertThrowsError(
            try fixture.service.create(
                edit: ScheduledTaskDefinitionEdit(
                    title: "Grant task",
                    prompt: "Run checks",
                    recurrence: .daily(hour: 8, minute: 0),
                    timeZoneIdentifier: "UTC",
                    providerID: "codex",
                    model: nil,
                    effort: "medium",
                    permissionMode: "default",
                    workspaceKind: .privateWorkspace,
                    workspaceStrategy: .worktree,
                    grantedRoots: ["/tmp/grant/", "/tmp/grant"],
                    project: nil
                )
            )
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskMutationError, .workspaceRootsChanged)
        }
    }

    func testCreateRejectsProjectWhoseCanonicalTargetChanged() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ScheduledTaskMutationProject-\(UUID().uuidString)", isDirectory: true)
        let projectURL = root.appendingPathComponent("Project", isDirectory: true)
        let replacementURL = root.appendingPathComponent("Replacement", isDirectory: true)
        try FileManager.default.createDirectory(at: projectURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: replacementURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let project = Project(path: projectURL.path, name: "Project")
        try FileManager.default.removeItem(at: projectURL)
        try FileManager.default.createSymbolicLink(at: projectURL, withDestinationURL: replacementURL)

        XCTAssertThrowsError(
            try fixture.service.create(
                edit: ScheduledTaskDefinitionEdit(
                    title: "Project task",
                    prompt: "Run checks",
                    recurrence: .daily(hour: 8, minute: 0),
                    timeZoneIdentifier: "UTC",
                    providerID: "codex",
                    model: nil,
                    effort: "medium",
                    permissionMode: "default",
                    workspaceKind: .project,
                    workspaceStrategy: .worktree,
                    grantedRoots: [],
                    project: project
                )
            )
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskMutationError, .workspaceRootsChanged)
        }
    }
}
