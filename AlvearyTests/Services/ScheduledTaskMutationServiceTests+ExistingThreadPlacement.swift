import Foundation
import SwiftData
import XCTest

@testable import Alveary

/// A schedule does not own its target's sidebar placement: saving one leaves the thread's pin,
/// section, and project exactly where the user put them.
@MainActor
extension ScheduledTaskMutationServiceTests {
    func testCreateLeavesAnUnpinnedExistingThreadTargetUnpinned() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let neighbor = AgentThread(name: "Already pinned", isPinned: true, mode: .task)
        neighbor.pinnedSortOrder = 0
        let target = try insertUnpinnedTarget(fixture: fixture, name: "Release chat", conversationID: "release-main")
        fixture.context.insert(neighbor)
        try fixture.context.save()

        let definition = try fixture.service.create(edit: existingThreadEdit(targetThread: target))

        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertFalse(target.isPinned)
        XCTAssertNil(target.pinnedSortOrder)
        XCTAssertEqual(neighbor.pinnedSortOrder, 0)
    }

    func testEditLeavesAnUnpinnedExistingThreadTargetUnpinned() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let definition = try fixture.insertDefinition(id: "retarget")
        let target = try insertUnpinnedTarget(fixture: fixture, name: "Release chat", conversationID: "release-main")

        try fixture.service.edit(
            definitionID: definition.id,
            edit: existingThreadEdit(targetThread: target)
        )

        XCTAssertEqual(definition.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertFalse(target.isPinned)
        XCTAssertNil(target.pinnedSortOrder)
    }

    func testCreateLeavesAnAlreadyPinnedTargetInPlace() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let target = try insertUnpinnedTarget(fixture: fixture, name: "Pinned", conversationID: "pinned-main")
        target.isPinned = true
        target.pinnedSortOrder = 3
        try fixture.context.save()

        try fixture.service.create(edit: existingThreadEdit(targetThread: target))

        XCTAssertTrue(target.isPinned)
        XCTAssertEqual(target.pinnedSortOrder, 3)
    }

    /// Section membership is the other half of placement, and the one an auto-pin used to hide:
    /// a pinned thread renders above every section.
    func testCreateLeavesTheTargetsCustomSectionMembershipIntact() throws {
        let fixture = try ScheduledTaskMutationFixture()
        let section = SidebarSection(kind: .custom, name: "Chores", sortOrder: 3)
        let target = try insertUnpinnedTarget(fixture: fixture, name: "Chore chat", conversationID: "chore-main")
        target.customSection = section
        fixture.context.insert(section)
        try fixture.context.save()

        try fixture.service.create(edit: existingThreadEdit(targetThread: target))

        XCTAssertEqual(target.customSection?.id, section.id)
        XCTAssertFalse(target.isPinned)
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
