import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testDeletingANestedTaskFallsBackToItsProjectSiblings() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Home", path: "/tmp/nested-delete-fallback")
        let sibling = AgentThread(name: "Sibling", project: project)
        sibling.conversations = [Conversation(id: "nested-delete-sibling", provider: "claude", thread: sibling)]
        project.threads.append(sibling)
        let task = AgentThread(name: "Nested", mode: .task, project: project)
        task.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/nested-delete-workspace",
            ownershipStrategy: .projectLocal
        )
        task.conversations = [Conversation(id: "nested-delete-task", provider: "claude", thread: task)]
        fixture.context.insert(sibling)
        fixture.context.insert(task)
        try fixture.context.save()
        let view = SidebarView(viewModel: fixture.viewModel, appState: AppState())

        // Placement decides the fallback: the task lived in the project, so deletion selects a
        // project sibling instead of jumping to the Tasks section or a blank composer.
        XCTAssertEqual(view.selectionAfterDeletingThread(task), .thread(sibling))
    }
}
