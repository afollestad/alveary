import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskModelTests {
    func testExistingThreadDestinationAndRunTargetRoundTrip() throws {
        let container = try makeScheduledTaskDestinationContainer()
        let context = ModelContext(container)
        let target = AgentThread(name: "Pinned target", isPinned: true, mode: .task)
        let conversation = Conversation(id: "target-main", provider: "codex", thread: target)
        target.conversations = [conversation]
        let task = ScheduledTask(
            title: "Attached schedule",
            prompt: "Continue here.",
            destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex",
            targetThread: target
        )
        let targetSnapshot = ScheduledTaskTargetSnapshot(
            conversationID: conversation.id,
            threadName: target.name,
            providerID: "codex",
            model: "gpt-5",
            effort: "high",
            permissionMode: "default",
            planModeEnabled: false,
            speedMode: AgentSpeedMode.standard.rawValue,
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: "/tmp/target",
            grantedRoots: []
        )
        let run = ScheduledTaskRun(
            snapshotting: task,
            occurrenceID: "attached-occurrence",
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            targetSnapshot: targetSnapshot
        )
        context.insert(task)
        context.insert(run)
        try context.save()

        let fetchedTask = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTask>()).first)
        let fetchedRun = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertEqual(fetchedTask.destination, .existingThread)
        XCTAssertEqual(fetchedTask.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertEqual(fetchedRun.destinationSnapshot, .existingThread)
        XCTAssertEqual(fetchedRun.targetConversationIDSnapshot, conversation.id)
        XCTAssertEqual(fetchedRun.targetThread?.persistentModelID, target.persistentModelID)
        XCTAssertNil(fetchedRun.thread)
    }

    func testUnknownDestinationRawValuesFailClosed() throws {
        let container = try makeScheduledTaskDestinationContainer()
        let context = ModelContext(container)
        let task = ScheduledTask(
            title: "Future schedule",
            prompt: "Perform the work.",
            destination: .newThreadPerRun,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex"
        )
        context.insert(task)
        // Snapshot while the destination is still valid; `init(snapshotting:)` fails closed on
        // an unknown one by design.
        let run = ScheduledTaskRun(
            snapshotting: task,
            occurrenceID: "future-occurrence",
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled
        )
        task.destinationRawValue = "future-destination"
        task.reusedThread = AgentThread(name: "Linked", mode: .task)
        run.destinationRawValueSnapshot = "future-destination"

        XCTAssertEqual(task.destination, .newThreadPerRun)
        XCTAssertNil(task.decodedDestination)
        // Safety gates never route an unknown destination at a thread.
        XCTAssertNil(task.runTargetThread)
        XCTAssertNil(run.decodedDestinationSnapshot)
    }

    func testPerRunDestinationKeepsItsFrozenRawValue() {
        // Every stored row carrying "newThread" means the per-run behavior; the case was renamed
        // around the raw value, and changing it would silently re-destine old schedules.
        XCTAssertEqual(ScheduledTaskDestination.newThreadPerRun.rawValue, "newThread")
        XCTAssertEqual(ScheduledTaskDestination(rawValue: "newThread"), .newThreadPerRun)
    }

    func testReusedThreadDestinationRoundTripsAndSnapshotsTargetIdentity() throws {
        let container = try makeScheduledTaskDestinationContainer()
        let context = ModelContext(container)
        let reused = AgentThread(name: "Rolling thread", mode: .task)
        let conversation = Conversation(id: "reused-main", provider: "codex", thread: reused)
        reused.conversations = [conversation]
        let task = ScheduledTask(
            title: "Rolling schedule",
            prompt: "Continue here.",
            destination: .reusedThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex"
        )
        task.reusedThread = reused
        let run = ScheduledTaskRun(
            snapshotting: task,
            occurrenceID: "reused-occurrence",
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            reusedTarget: ScheduledTaskReusedTarget(
                conversationID: conversation.id,
                threadName: reused.name,
                threadID: reused.persistentModelID
            )
        )
        context.insert(task)
        context.insert(run)
        try context.save()

        let fetchedTask = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTask>()).first)
        let fetchedRun = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertEqual(fetchedTask.destination, .reusedThread)
        XCTAssertEqual(fetchedTask.runTargetThread?.persistentModelID, reused.persistentModelID)
        // The reused target contributes identity only; the definition stays authoritative for
        // provider and settings, unlike an existing-thread target snapshot.
        XCTAssertEqual(fetchedRun.destinationSnapshot, .reusedThread)
        XCTAssertEqual(fetchedRun.targetConversationIDSnapshot, conversation.id)
        XCTAssertEqual(fetchedRun.targetThread?.persistentModelID, reused.persistentModelID)
        XCTAssertEqual(fetchedRun.providerIDSnapshot, task.providerID)
        XCTAssertNil(fetchedRun.planModeEnabledSnapshot)
        XCTAssertNil(fetchedRun.speedModeSnapshot)
        XCTAssertNil(fetchedRun.thread)
    }

    func testReusedThreadSnapshottingIgnoresARepointedLink() throws {
        let container = try makeScheduledTaskDestinationContainer()
        let context = ModelContext(container)
        let original = AgentThread(name: "Original", mode: .task)
        let originalConversation = Conversation(id: "original-main", provider: "codex", thread: original)
        original.conversations = [originalConversation]
        let replacement = AgentThread(name: "Replacement", mode: .task)
        let task = ScheduledTask(
            title: "Rolling schedule",
            prompt: "Continue here.",
            destination: .reusedThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex"
        )
        context.insert(task)
        context.insert(original)
        context.insert(replacement)
        try context.save()
        // The claim captured `original`, but the link moved before snapshotting.
        task.reusedThread = replacement

        let run = ScheduledTaskRun(
            snapshotting: task,
            occurrenceID: "repointed-occurrence",
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled,
            reusedTarget: ScheduledTaskReusedTarget(
                conversationID: originalConversation.id,
                threadName: original.name,
                threadID: original.persistentModelID
            )
        )

        XCTAssertNil(run.targetThread)
        XCTAssertNil(run.targetConversationIDSnapshot)
    }

    func testDeletingReusedThreadNullifiesTheLinkWithoutBlocking() throws {
        let container = try makeScheduledTaskDestinationContainer()
        let context = ModelContext(container)
        let reused = AgentThread(name: "Rolling thread", mode: .task)
        let task = ScheduledTask(
            title: "Rolling schedule",
            prompt: "Continue here.",
            destination: .reusedThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex"
        )
        task.reusedThread = reused
        context.insert(task)
        try context.save()

        // The reuse link must never feed the archive/delete attachment block.
        XCTAssertNil(reused.blockingScheduledTaskAttachment)
        context.delete(reused)
        try context.save()

        let fetchedTask = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTask>()).first)
        XCTAssertNil(fetchedTask.reusedThread)
        XCTAssertEqual(fetchedTask.destination, .reusedThread)
    }

    func testDeletingThreadSectionNullifiesTheDefinitionButKeepsTheRunSnapshot() throws {
        let container = try makeSectionedScheduledTaskContainer()
        let context = ModelContext(container)
        let section = SidebarSection(id: "reports", kind: .custom, name: "Reports", sortOrder: 3)
        let task = ScheduledTask(
            title: "Sectioned schedule",
            prompt: "Do the work.",
            destination: .reusedThread,
            recurrence: .daily(hour: 9, minute: 0),
            timeZoneIdentifier: "America/Chicago",
            providerID: "codex"
        )
        context.insert(section)
        context.insert(task)
        task.threadSection = section
        try context.save()
        let run = ScheduledTaskRun(
            snapshotting: task,
            occurrenceID: "sectioned-occurrence",
            occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
            triggerKind: .scheduled
        )
        context.insert(run)
        try context.save()
        XCTAssertEqual(run.threadSectionIDSnapshot, "reports")

        context.delete(section)
        try context.save()

        let fetchedTask = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTask>()).first)
        let fetchedRun = try XCTUnwrap(try context.fetch(FetchDescriptor<ScheduledTaskRun>()).first)
        XCTAssertNil(fetchedTask.threadSection)
        // The snapshot column is frozen claim intent; materialization degrades it to `Tasks`.
        XCTAssertEqual(fetchedRun.threadSectionIDSnapshot, "reports")
    }

    private func makeSectionedScheduledTaskContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            SidebarSection.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func makeScheduledTaskDestinationContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }
}
