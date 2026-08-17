import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunMaterializerTests {
    func testFirstReuseRunCreatesThreadAndLinksTheDefinition() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let definition = try fixture.insertReuseDefinition()
        let run = try fixture.insertRun(
            id: "reuse-first-run",
            occurrenceID: "reuse-first-occurrence",
            destination: .reusedThread
        )
        run.scheduledTask = definition
        try fixture.context.save()

        let result = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)

        let thread = try XCTUnwrap(run.thread)
        XCTAssertEqual(result.threadID, thread.persistentModelID)
        // The promoted-workspace save is what links; a shell without a real workspace must not.
        XCTAssertEqual(definition.reusedThread?.persistentModelID, thread.persistentModelID)
        XCTAssertEqual(definition.revision, 1)
        XCTAssertNil(run.targetThread)
        XCTAssertFalse(thread.isPinned)
    }

    func testSecondReuseRunPostsIntoTheLinkedThreadAndReassertsSettings() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let workspaceRoot = try fixture.createDirectory(named: "ReusedWorkspace")
        let thread = AgentThread(
            name: "Rolling thread",
            permissionMode: "default",
            effort: "medium",
            model: "gpt-4",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: workspaceRoot.path,
                ownershipStrategy: .privateOwned
            )
        )
        let conversation = Conversation(id: "reused-main", provider: "codex", thread: thread)
        thread.conversations = [conversation]
        fixture.context.insert(thread)
        try fixture.context.save()
        let run = try fixture.insertRun(
            id: "reuse-second-run",
            occurrenceID: "reuse-second-occurrence",
            destination: .reusedThread,
            targetThread: thread,
            targetConversationID: conversation.id
        )

        let result = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)

        XCTAssertEqual(result.threadID, thread.persistentModelID)
        XCTAssertEqual(result.conversationID, conversation.id)
        XCTAssertEqual(result.workspace.primaryRoot, CanonicalPath.normalize(workspaceRoot.path))
        // `run.thread` is to-one with the creating run; a posting run must never claim it.
        XCTAssertNil(run.thread)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        // Automated spawns read the thread's stored fields, so the definition's settings only
        // take effect because materialization re-asserts the snapshot here.
        XCTAssertEqual(thread.model, "gpt-5")
        XCTAssertEqual(thread.effort, "high")
        XCTAssertEqual(thread.permissionMode, "acceptEdits")
        XCTAssertEqual(conversation.events.first?.type, ConversationEventRecord.scheduledTaskNoteType)
    }

    func testReuseRunSelfHealsWhenTheClaimedThreadWasArchived() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let workspaceRoot = try fixture.createDirectory(named: "ArchivedReusedWorkspace")
        let archived = AgentThread(
            name: "Archived rolling thread",
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: workspaceRoot.path,
                ownershipStrategy: .privateOwned
            )
        )
        archived.archivedAt = Date(timeIntervalSince1970: 1_799_999_000)
        let conversation = Conversation(id: "archived-main", provider: "codex", thread: archived)
        archived.conversations = [conversation]
        let definition = try fixture.insertReuseDefinition()
        definition.reusedThread = archived
        fixture.context.insert(archived)
        try fixture.context.save()
        let run = try fixture.insertRun(
            id: "reuse-heal-run",
            occurrenceID: "reuse-heal-occurrence",
            destination: .reusedThread,
            targetThread: archived,
            targetConversationID: conversation.id
        )
        run.scheduledTask = definition
        try fixture.context.save()

        let result = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)

        // The unusable claim detaches and a replacement is created in its place…
        let replacement = try XCTUnwrap(run.thread)
        XCTAssertNil(run.targetThread)
        XCTAssertEqual(result.threadID, replacement.persistentModelID)
        XCTAssertNotEqual(replacement.persistentModelID, archived.persistentModelID)
        // …and the stale link is overwritten, so the next claim reuses the replacement instead
        // of minting fresh threads forever.
        XCTAssertEqual(definition.reusedThread?.persistentModelID, replacement.persistentModelID)
        XCTAssertEqual(conversation.events.count, 0)
    }

    func testReuseRunSeedsTheSnapshottedSectionAndDegradesWhenItVanished() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        fixture.context.insert(section)
        try fixture.context.save()
        let sectionedRun = try fixture.insertRun(
            id: "sectioned-run",
            occurrenceID: "sectioned-occurrence",
            destination: .reusedThread
        )
        sectionedRun.threadSectionIDSnapshot = "reports"
        let staleRun = try fixture.insertRun(
            id: "stale-section-run",
            occurrenceID: "stale-section-occurrence",
            destination: .newThreadPerRun
        )
        staleRun.threadSectionIDSnapshot = "vanished"
        try fixture.context.save()

        _ = try await fixture.makeMaterializer().materialize(runID: sectionedRun.persistentModelID)
        _ = try await fixture.makeMaterializer().materialize(runID: staleRun.persistentModelID)

        XCTAssertEqual(sectionedRun.thread?.customSection?.id, "reports")
        // A vanished section degrades to `Tasks` instead of failing an unattended run.
        XCTAssertNil(try XCTUnwrap(staleRun.thread).customSection)
    }
}

extension ScheduledTaskRunMaterializerFixture {
    func insertReuseDefinition() throws -> ScheduledTask {
        let definition = ScheduledTask(
            id: "definition",
            title: "Review changes",
            prompt: "Review the scheduled changes.",
            destination: .reusedThread,
            recurrence: .daily(hour: 2, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex"
        )
        context.insert(definition)
        try context.save()
        return definition
    }
}
