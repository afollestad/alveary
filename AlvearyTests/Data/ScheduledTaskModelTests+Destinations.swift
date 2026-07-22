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
