import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testMoveTaskIntoProjectAddsTheFolderAndLeavesTheTaskWhereItIs() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "grant-target")
        let project = try fixture.insertProject(name: "Alveary", path: projectPath)
        let task = try await fixture.materializedTask(named: "Ship the drop targets")
        let workspaceRoot = try XCTUnwrap(task.taskWorkspaceDescriptor?.primaryRoot)
        let conversationID = try XCTUnwrap(task.conversations.first?.id)

        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )

        let granted = try fixture.requireThread(task.persistentModelID)
        XCTAssertEqual(granted.taskWorkspaceDescriptor?.grantedRoots, [projectPath])
        // It now renders inside the project, but stays a Task working in its own directory.
        XCTAssertEqual(granted.project?.persistentModelID, project.persistentModelID)
        XCTAssertEqual(granted.mode, .task)
        XCTAssertEqual(granted.taskWorkspaceDescriptor?.primaryRoot, workspaceRoot)
        let snapshot = try fixture.renderSnapshot()
        XCTAssertEqual(snapshot.activeThreads(for: project).map(\.persistentModelID), [task.persistentModelID])
        XCTAssertTrue(snapshot.activeTaskThreads.isEmpty)
        XCTAssertEqual(granted.primaryWorkingDirectory, workspaceRoot)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceRoot))
        // Suspend, never destroy: the provider session survives so the next turn resumes history.
        let suspended = await fixture.agentsManager.recordedSuspendCalls
        XCTAssertEqual(suspended, [conversationID])
        let destroyed = await fixture.agentsManager.recordedDestroyCalls
        XCTAssertTrue(destroyed.isEmpty)
    }

    func testMoveTaskIntoProjectPreservesExistingGrants() async throws {
        let fixture = try SidebarTestFixture()
        let existingPath = try fixture.makeTemporaryDirectory(named: "grant-existing")
        let projectPath = try fixture.makeTemporaryDirectory(named: "grant-second")
        let project = try fixture.insertProject(name: "Second", path: projectPath)
        let task = try await fixture.materializedTask(named: "Has a grant")
        let workspace = try XCTUnwrap(task.taskWorkspaceDescriptor)
        task.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: workspace.primaryRoot,
            grantedRoots: [existingPath],
            ownershipStrategy: workspace.ownershipStrategy,
            ownershipMarkerID: workspace.ownershipMarkerID,
            sourceProjectPath: workspace.sourceProjectPath
        )
        try fixture.context.save()

        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )

        let granted = try fixture.requireThread(task.persistentModelID)
        XCTAssertEqual(granted.taskWorkspaceDescriptor?.grantedRoots.sorted(), [existingPath, projectPath].sorted())
    }

    func testMoveTaskIntoProjectRejectsAProjectItIsAlreadyIn() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "grant-duplicate")
        let project = try fixture.insertProject(name: "Duplicate", path: projectPath)
        let task = try await fixture.materializedTask(named: "Already granted")

        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )
        await XCTAssertThrowsErrorAsync {
            try await fixture.viewModel.moveTaskIntoProject(
                task.persistentModelID,
                projectID: project.persistentModelID
            )
        }

        let granted = try fixture.requireThread(task.persistentModelID)
        XCTAssertEqual(granted.taskWorkspaceDescriptor?.grantedRoots, [projectPath])
    }

    func testMoveTaskIntoProjectRejectsIneligibleSources() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "grant-rejects")
        let project = try fixture.insertProject(name: "Target", path: projectPath)
        let projectThread = AgentThread(name: "Project thread", project: project)
        projectThread.conversations = [Conversation(id: "grant-project-thread", provider: "claude", thread: projectThread)]
        let archived = try await fixture.materializedTask(named: "Archived")
        archived.archivedAt = Date()
        let multiConversation = try await fixture.materializedTask(named: "Two tabs")
        multiConversation.conversations.append(
            Conversation(id: "grant-second-tab", provider: "claude", thread: multiConversation)
        )
        let draft = try await fixture.viewModel.openTaskDraft()
        fixture.context.insert(projectThread)
        try fixture.context.save()

        for threadID in [
            projectThread.persistentModelID,
            archived.persistentModelID,
            multiConversation.persistentModelID,
            draft.persistentModelID
        ] {
            await XCTAssertThrowsErrorAsync {
                try await fixture.viewModel.moveTaskIntoProject(
                    threadID,
                    projectID: project.persistentModelID
                )
            }
        }
        XCTAssertTrue(try fixture.requireThread(archived.persistentModelID).taskGrantedRoots.isEmpty)
        XCTAssertTrue(try fixture.requireThread(multiConversation.persistentModelID).taskGrantedRoots.isEmpty)
    }

    func testMoveTaskIntoProjectRejectsBusyAndUnresolvedApprovalSources() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "grant-busy")
        let project = try fixture.insertProject(name: "Target", path: projectPath)
        let busy = try await fixture.materializedTask(named: "Busy")
        let awaitingApproval = try await fixture.materializedTask(named: "Awaiting approval")
        let busyConversationID = try XCTUnwrap(busy.conversations.first?.id)
        let approvalConversationID = try XCTUnwrap(awaitingApproval.conversations.first?.id)
        await fixture.agentsManager.setStatus(.busy, for: busyConversationID)
        fixture.context.insert(ConversationEventRecord(
            conversationId: approvalConversationID,
            type: "tool_approval",
            toolId: "tool-1",
            toolName: "Bash",
            timestamp: Date(timeIntervalSince1970: 50)
        ))
        try fixture.context.save()

        for threadID in [busy.persistentModelID, awaitingApproval.persistentModelID] {
            await XCTAssertThrowsErrorAsync {
                try await fixture.viewModel.moveTaskIntoProject(
                    threadID,
                    projectID: project.persistentModelID
                )
            }
            XCTAssertTrue(try fixture.requireThread(threadID).taskGrantedRoots.isEmpty)
        }
    }

    func testMoveTaskIntoProjectRejectsScheduledAttachments() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "grant-scheduled")
        let project = try fixture.insertProject(name: "Target", path: projectPath)
        let task = try await fixture.materializedTask(named: "Scheduled")
        fixture.context.insert(ScheduledTask(
            title: "Nightly sweep",
            prompt: "Continue in the task.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            createdAt: Date(timeIntervalSince1970: 100),
            targetThread: task
        ))
        try fixture.context.save()

        await XCTAssertThrowsErrorAsync {
            try await fixture.viewModel.moveTaskIntoProject(
                task.persistentModelID,
                projectID: project.persistentModelID
            )
        }
        XCTAssertTrue(try fixture.requireThread(task.persistentModelID).taskGrantedRoots.isEmpty)
    }

    func testMoveTaskIntoProjectRejectsAMissingProjectFolder() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Gone", path: "/tmp/grant-missing-\(UUID().uuidString)")
        let task = try await fixture.materializedTask(named: "Missing folder")

        await XCTAssertThrowsErrorAsync {
            try await fixture.viewModel.moveTaskIntoProject(
                task.persistentModelID,
                projectID: project.persistentModelID
            )
        }
        XCTAssertTrue(try fixture.requireThread(task.persistentModelID).taskGrantedRoots.isEmpty)
    }

    func testDroppingANestedTaskOnTasksLeavesTheProjectButKeepsTheGrant() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "detach-target")
        let project = try fixture.insertProject(name: "Alveary", path: projectPath)
        let task = try await fixture.materializedTask(named: "Nested")
        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        )

        XCTAssertTrue(didCommit)
        let detached = try fixture.requireThread(task.persistentModelID)
        XCTAssertNil(detached.project)
        // Placement is the only thing that changes: revoking access could break work in flight.
        XCTAssertEqual(detached.taskWorkspaceDescriptor?.grantedRoots, [projectPath])
        let snapshot = try fixture.renderSnapshot()
        XCTAssertEqual(snapshot.activeTaskThreads.map(\.persistentModelID), [task.persistentModelID])
        XCTAssertTrue(snapshot.activeThreads(for: project).isEmpty)
    }

    func testTasksDropIgnoresATaskThatIsAlreadyProjectless() async throws {
        let fixture = try SidebarTestFixture()
        let task = try await fixture.materializedTask(named: "Already loose")

        XCTAssertFalse(try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        ))
        XCTAssertNil(try fixture.requireThread(task.persistentModelID).project)
    }

    func testDropIsPurePlacementWhenTheTaskAlreadyReachesTheFolder() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "already-granted")
        let project = try fixture.insertProject(name: "Alveary", path: projectPath)
        let task = try await fixture.materializedTask(named: "Round trip")

        let firstDrop = try fixture.viewModel.validateTaskProjectAccess(
            threadID: task.persistentModelID,
            projectID: project.persistentModelID
        )
        XCTAssertTrue(firstDrop.grantsNewAccess)
        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )
        _ = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        )

        // Dragged back out, the grant survives, so dropping in again authorizes nothing new and
        // the confirmation dialog is skipped.
        let secondDrop = try fixture.viewModel.validateTaskProjectAccess(
            threadID: task.persistentModelID,
            projectID: project.persistentModelID
        )
        XCTAssertFalse(secondDrop.grantsNewAccess)
    }

    func testDroppingAPinnedNestedTaskOnTasksActuallyLandsInTasks() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "pinned-nested")
        let project = try fixture.insertProject(name: "Alveary", path: projectPath)
        let task = try await fixture.materializedTask(named: "Pinned nested")
        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )
        // Pinning promotes it out of the unpinned project into a standalone Pinned row.
        try fixture.viewModel.setThreadPinned(try fixture.requireThread(task.persistentModelID), isPinned: true)

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .pinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .tasks, placement: .end)
        )

        XCTAssertTrue(didCommit)
        let dropped = try fixture.requireThread(task.persistentModelID)
        XCTAssertFalse(dropped.isPinned)
        // Dropping on Tasks must mean "belongs in Tasks", not "unpin back into the project".
        XCTAssertNil(dropped.project)
        XCTAssertEqual(
            try fixture.renderSnapshot().activeTaskThreads.map(\.persistentModelID),
            [task.persistentModelID]
        )
    }

    func testDroppingAPinnedTaskIntoAnUnpinnedProjectClearsThePin() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "unpinned-target")
        let project = try fixture.insertProject(name: "Alveary", path: projectPath)
        let task = try await fixture.materializedTask(named: "Pinned task")
        try fixture.viewModel.setThreadPinned(task, isPinned: true)

        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )

        // The project owns its children's placement, so the Task must stop drawing a standalone
        // Pinned row rather than rendering in both places.
        let moved = try fixture.requireThread(task.persistentModelID)
        XCTAssertFalse(moved.isPinned)
        XCTAssertNil(moved.pinnedSortOrder)
        XCTAssertEqual(moved.project?.persistentModelID, project.persistentModelID)
        let snapshot = try fixture.renderSnapshot()
        XCTAssertTrue(snapshot.pinnedItems.isEmpty)
        XCTAssertTrue(snapshot.activeTaskThreads.isEmpty)
        XCTAssertEqual(
            snapshot.activeThreads(for: project).map(\.persistentModelID),
            [task.persistentModelID]
        )
    }

    func testPinnedProjectChildTaskDraggedToPinnedIsNotASilentNoOp() async throws {
        let fixture = try SidebarTestFixture()
        let projectPath = try fixture.makeTemporaryDirectory(named: "pinned-parent")
        let project = try fixture.insertProject(name: "Pinned parent", path: projectPath)
        let task = try await fixture.materializedTask(named: "Child")
        try await fixture.viewModel.moveTaskIntoProject(
            task.persistentModelID,
            projectID: project.persistentModelID
        )
        try fixture.viewModel.setProjectPinned(project, isPinned: true)

        let didMove = try fixture.viewModel.commitSidebarDrop(
            dragItem: .unpinnedTask(task.persistentModelID),
            target: SidebarDropTarget(section: .pinned, placement: .end)
        )

        // The pinned project absorbs its children, so a pin can never take effect here. The drop
        // must report no movement rather than claiming success while changing nothing.
        XCTAssertFalse(didMove)
        let unchanged = try fixture.requireThread(task.persistentModelID)
        XCTAssertFalse(unchanged.isPinned)
        XCTAssertEqual(unchanged.project?.persistentModelID, project.persistentModelID)
    }
}
