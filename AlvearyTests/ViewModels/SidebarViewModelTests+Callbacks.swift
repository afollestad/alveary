import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchivingExactCallbackStopsItsRunAndRestoringLeavesSchedulePaused() async throws {
        let control = CallbackLifecycleControl()
        let fixture = try SidebarTestFixture(stopAndWaitForScheduledTaskRun: { try control.stop($0) })
        let target = try makeCallbackTarget(fixture)
        let run = ScheduledTaskRun(
            snapshotting: target.definition, occurrenceID: "callback", occurrenceAt: .now, triggerKind: .scheduled,
            targetSnapshot: nil
        )
        run.targetThread = target.thread
        run.targetConversationIDSnapshot = "callback-tab"
        run.status = .running
        fixture.context.insert(run)
        try fixture.context.save()
        control.onStop = { id in
            XCTAssertEqual(id, run.persistentModelID)
            XCTAssertNil(target.thread.archivedAt)
            XCTAssertEqual(target.definition.state, .active)
            run.status = .interrupted
            try fixture.context.save()
        }

        try await fixture.viewModel.archiveThread(target.thread)

        XCTAssertGreaterThan(control.stops, 0)
        XCTAssertNotNil(target.thread.archivedAt)
        XCTAssertEqual(target.definition.state, .paused)
        XCTAssertNil(target.definition.nextOccurrenceAt)
        XCTAssertNil(target.definition.pendingOccurrenceAt)
        XCTAssertEqual(target.definition.exactTargetConversationID, "callback-tab")
        try await fixture.viewModel.restoreThread(target.thread)
        XCTAssertEqual(target.definition.state, .paused)
        XCTAssertEqual(target.definition.resolvedTargetConversation?.id, "callback-tab")
    }

    func testTaskAndProjectDeletionRollbackAndPauseExactCallbacksWithoutRetargeting() async throws {
        for deleteProject in [false, true] {
            let control = CallbackLifecycleControl()
            let fixture = try SidebarTestFixture(saveDeletionCommit: { context in
                if control.failSave { throw CocoaError(.fileWriteUnknown) }
                try context.save()
            })
            let target = try makeCallbackTarget(fixture)
            let project = try XCTUnwrap(target.thread.project)
            let threadID = target.thread.persistentModelID
            control.failSave = true
            do {
                if deleteProject { try await fixture.viewModel.deleteProject(project) } else {
                    try await fixture.viewModel.deleteThread(target.thread)
                }
                XCTFail("Expected the deleting transaction to fail")
            } catch {}
            XCTAssertNotNil(fixture.context.resolveThread(id: threadID))
            XCTAssertEqual(target.definition.state, .active)
            XCTAssertEqual(target.definition.pendingOccurrenceAt, .distantFuture)
            control.failSave = false
            if deleteProject { try await fixture.viewModel.deleteProject(project) } else {
                try await fixture.viewModel.deleteThread(target.thread)
            }
            XCTAssertNil(fixture.context.resolveThread(id: threadID))
            XCTAssertEqual(target.definition.state, .paused)
            XCTAssertEqual(target.definition.destination, .existingThread)
            XCTAssertEqual(target.definition.exactTargetConversationID, "callback-tab")
            XCTAssertNil(target.definition.targetThread)
            XCTAssertNil(target.definition.pendingOccurrenceAt)
            XCTAssertNotNil(target.definition.pauseReason)
        }
    }

    private func makeCallbackTarget(_ fixture: SidebarTestFixture) throws -> (thread: AgentThread, definition: ScheduledTask) {
        let thread = try fixture.insertThread(
            projectName: "Callbacks", projectPath: "/tmp/callback-lifecycle", conversationIDs: ["main", "callback-tab"]
        )
        let definition = ScheduledTask(
            title: "Callback", prompt: "Hello", destination: .existingThread,
            recurrence: .daily(hour: 9, minute: 0), timeZoneIdentifier: "UTC", harnessID: "claude",
            nextOccurrenceAt: .distantFuture, pendingOccurrenceAt: .distantFuture, targetThread: thread
        )
        definition.exactTargetConversationID = "callback-tab"
        fixture.context.insert(definition)
        try fixture.context.save()
        return (thread, definition)
    }
}

@MainActor
private final class CallbackLifecycleControl {
    var onStop: ((PersistentIdentifier) throws -> Void)?
    var stops = 0
    var failSave = false

    func stop(_ id: PersistentIdentifier) throws {
        stops += 1
        try onStop?(id)
    }
}
