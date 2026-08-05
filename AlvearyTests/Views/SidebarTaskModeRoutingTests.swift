import XCTest

@testable import Alveary

@MainActor
final class SidebarTaskModeRoutingTests: XCTestCase {
    func testTaskMaterializationDoesNotExpandAttachedProject() {
        let notification = Notification(
            name: .threadDraftMaterialized,
            userInfo: [
                ThreadDraftNotificationKey.mode: AgentThreadMode.task.rawValue,
                ThreadDraftNotificationKey.projectPath: "/tmp/attached-task-materialization"
            ]
        )

        XCTAssertEqual(sidebarDraftMaterializedMode(notification), .task)
        XCTAssertNil(sidebarProjectPathToExpandAfterDraftMaterialization(notification))
    }

    func testLegacyProjectMaterializationStillExpandsProject() {
        let notification = Notification(
            name: .threadDraftMaterialized,
            userInfo: [ThreadDraftNotificationKey.projectPath: "/tmp/legacy-project-materialization"]
        )

        XCTAssertEqual(sidebarDraftMaterializedMode(notification), .project)
        XCTAssertEqual(
            sidebarProjectPathToExpandAfterDraftMaterialization(notification),
            "/tmp/legacy-project-materialization"
        )
    }

    func testTaskModeSelectionDoesNotExpandAttachedProject() {
        let project = Project(path: "/tmp/attached-task-expansion", name: "Source")
        let task = AgentThread(
            name: "Attached task",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: project.path,
                ownershipStrategy: .projectLocal,
                sourceProjectPath: project.path
            ),
            project: project
        )

        let projectPath = sidebarProjectPathToExpand(for: .thread(task), resolveThread: { _ in task })

        XCTAssertNil(projectPath)
    }

    // Arrow-key traversal has to be able to rest on a collapsed project row: if selecting one
    // expanded it, left-arrow collapse would be undone as soon as the selection returned.
    func testProjectSelectionDoesNotExpandItsOwnRow() {
        let project = Project(path: "/tmp/project-selection-expansion", name: "Alpha")

        let projectPath = sidebarProjectPathToExpand(for: .project(project), resolveThread: { _ in nil })

        XCTAssertNil(projectPath)
    }
}
