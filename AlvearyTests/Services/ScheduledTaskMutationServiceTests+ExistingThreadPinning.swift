import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// An existing-thread schedule posts into a thread the user has to be able to reach, so the
/// mutation pins an unpinned target as part of its own save.
@MainActor
extension ScheduledTaskMutationServiceTests {
    func testCreatePinsAnUnpinnedExistingThreadTarget() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let neighbor = AgentThread(name: "Already pinned", isPinned: true, mode: .task)
        neighbor.pinnedSortOrder = 0
        let target = try insertUnpinnedTarget(fixture: fixture, name: "Release chat", conversationID: "release-main")
        fixture.context.insert(neighbor)
        try fixture.context.save()

        let definition = try fixture.service.create(edit: existingThreadEdit(targetThread: target))

        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertTrue(target.isPinned)
        XCTAssertEqual(target.pinnedSortOrder, 1)
    }

    func testEditPinsAnUnpinnedExistingThreadTarget() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition(id: "retarget")
        let target = try insertUnpinnedTarget(fixture: fixture, name: "Release chat", conversationID: "release-main")

        try fixture.service.edit(
            definitionID: definition.id,
            edit: existingThreadEdit(targetThread: target)
        )

        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertTrue(target.isPinned)
        XCTAssertEqual(target.pinnedSortOrder, 0)
    }

    /// The append reads the highest assigned order rather than a count, so it stays collision-free
    /// without the sidebar's dense renumbering pass.
    func testPinningTwoTargetsAssignsDistinctOrders() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let first = try insertUnpinnedTarget(fixture: fixture, name: "First", conversationID: "first-main")
        let second = try insertUnpinnedTarget(fixture: fixture, name: "Second", conversationID: "second-main")

        try fixture.service.create(edit: existingThreadEdit(targetThread: first))
        try fixture.service.create(edit: existingThreadEdit(targetThread: second))

        XCTAssertEqual(first.pinnedSortOrder, 0)
        XCTAssertEqual(second.pinnedSortOrder, 1)
    }

    func testCreateLeavesAnAlreadyPinnedTargetInPlace() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let target = try insertUnpinnedTarget(fixture: fixture, name: "Pinned", conversationID: "pinned-main")
        target.isPinned = true
        target.pinnedSortOrder = 3
        try fixture.context.save()

        try fixture.service.create(edit: existingThreadEdit(targetThread: target))

        XCTAssertEqual(target.pinnedSortOrder, 3)
    }
}

private extension ScheduledTaskMutationServiceTests {
    func insertUnpinnedTarget(
        fixture: ScheduledTaskMutationFixture,
        name: String,
        conversationID: String
    ) throws -> AgentThread {
        let target = AgentThread(name: name, mode: .task)
        target.conversations = [Conversation(id: conversationID, provider: "codex", thread: target)]
        fixture.context.insert(target)
        try fixture.context.save()
        return target
    }

    func existingThreadEdit(targetThread: AgentThread) -> ScheduledTaskDefinitionEdit {
        ScheduledTaskDefinitionEdit(
            title: "Continue existing work",
            prompt: "Review the latest state.",
            destination: .existingThread,
            recurrence: .daily(hour: 8, minute: 0),
            timeZoneIdentifier: "UTC",
            providerID: "codex",
            model: nil,
            effort: "medium",
            permissionMode: "default",
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: [],
            project: nil,
            targetThread: targetThread
        )
    }
}
