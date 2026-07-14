import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunRecoveryCoordinatorTests {
    func testRecoverySupersedesLateInteractionsOnTerminalRuns() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 900_000)
        let completed = fixture.insertRun(
            status: .success,
            occurrenceAt: actionDate.addingTimeInterval(-30),
            withPendingApproval: true
        )
        completed.requiresFinalizationRecovery = true
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        let approval = try XCTUnwrap(completed.thread?.conversations.first?.events.first {
            $0.type == "tool_approval"
        })
        let question = try XCTUnwrap(completed.thread?.conversations.first?.events.first {
            $0.type == "tool_call"
        })
        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertTrue(result.interruptedRunIDs.isEmpty)
        XCTAssertEqual(completed.status, .success)
        XCTAssertEqual(approval.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertEqual(question.content, ChatItemGrouper.handledPromptSummary)
        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, 0)
    }

    func testRecoveryPreservesManualInteractionsOnFinalizedTerminalRuns() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 910_000)
        let completed = fixture.insertRun(
            status: .success,
            occurrenceAt: actionDate.addingTimeInterval(-30),
            withPendingApproval: true
        )
        XCTAssertFalse(completed.requiresFinalizationRecovery)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        let approval = try XCTUnwrap(completed.thread?.conversations.first?.events.first {
            $0.type == "tool_approval"
        })
        let question = try XCTUnwrap(completed.thread?.conversations.first?.events.first {
            $0.type == "tool_call"
        })
        XCTAssertNil(approval.toolApprovalStatus)
        XCTAssertNil(question.content)
        XCTAssertEqual(completed.status, .success)
    }

    func testRecoverySaveFailureRollsBackShellUnreadAndInteractionsAfterFlushingPreexistingChanges() throws {
        let saveProbe = ScheduledTaskRecoverySaveProbe(failingCall: 2)
        let fixture = try ScheduledTaskRecoveryFixture(saveChanges: saveProbe.save)
        let actionDate = Date(timeIntervalSinceReferenceDate: 6_500_000)
        let threadless = fixture.insertRun(
            status: .running,
            occurrenceAt: actionDate.addingTimeInterval(-60),
            withThread: false
        )
        let interactive = fixture.insertRun(
            status: .waiting,
            occurrenceAt: actionDate.addingTimeInterval(-30),
            withPendingApproval: true
        )
        try fixture.context.save()
        let threadlessID = threadless.persistentModelID
        let interactiveID = interactive.persistentModelID

        interactive.lastError = "preexisting unsaved state"

        XCTAssertThrowsError(
            try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }
        ) { error in
            XCTAssertEqual(error as? RecoverySaveTestError, .forcedFailure)
        }

        XCTAssertEqual(saveProbe.saveCalls, 2)
        let verificationContext = ModelContext(fixture.container)
        let restoredThreadless = try XCTUnwrap(
            verificationContext.resolveScheduledTaskRun(id: threadlessID)
        )
        let restoredInteractive = try XCTUnwrap(
            verificationContext.resolveScheduledTaskRun(id: interactiveID)
        )
        XCTAssertEqual(restoredThreadless.status, .running)
        XCTAssertNil(restoredThreadless.finishedAt)
        XCTAssertNil(restoredThreadless.thread)
        XCTAssertEqual(restoredInteractive.status, .waiting)
        XCTAssertNil(restoredInteractive.finishedAt)
        XCTAssertEqual(restoredInteractive.lastError, "preexisting unsaved state")
        XCTAssertFalse(restoredInteractive.thread?.conversations.first(where: \.isMain)?.isUnread == true)
        XCTAssertEqual(
            restoredInteractive.thread?.conversations.first?.events.first(where: { $0.type == "tool_approval" })?.toolApprovalStatus,
            nil
        )
        XCTAssertEqual(
            restoredInteractive.thread?.conversations.first?.events.first(where: { $0.type == "tool_call" })?.content,
            nil
        )
        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, 0)
        XCTAssertTrue(fixture.notificationManager.handleEventCalls.isEmpty)
    }

    func testTerminationSaveFailureRollsBackStateBeforeControllerFlushOrNotification() throws {
        let saveProbe = ScheduledTaskRecoverySaveProbe(failingCall: 1)
        let fixture = try ScheduledTaskRecoveryFixture(saveChanges: saveProbe.save)
        let actionDate = Date(timeIntervalSinceReferenceDate: 6_600_000)
        let threadless = fixture.insertRun(
            status: .preparing,
            occurrenceAt: actionDate.addingTimeInterval(-60),
            withThread: false
        )
        let interactive = fixture.insertRun(
            status: .waiting,
            occurrenceAt: actionDate.addingTimeInterval(-30),
            withPendingApproval: true
        )
        let originalModifiedAt = interactive.thread?.modifiedAt
        try fixture.context.save()
        let threadlessID = threadless.persistentModelID
        let interactiveID = interactive.persistentModelID

        XCTAssertThrowsError(
            try fixture.coordinator.prepareForTermination(at: actionDate)
        ) { error in
            XCTAssertEqual(error as? RecoverySaveTestError, .forcedFailure)
        }

        XCTAssertEqual(saveProbe.saveCalls, 1)
        let verificationContext = ModelContext(fixture.container)
        let restoredThreadless = try XCTUnwrap(
            verificationContext.resolveScheduledTaskRun(id: threadlessID)
        )
        let restoredInteractive = try XCTUnwrap(
            verificationContext.resolveScheduledTaskRun(id: interactiveID)
        )
        XCTAssertEqual(restoredThreadless.status, .preparing)
        XCTAssertNil(restoredThreadless.finishedAt)
        XCTAssertNil(restoredThreadless.thread)
        XCTAssertEqual(restoredInteractive.status, .waiting)
        XCTAssertNil(restoredInteractive.finishedAt)
        XCTAssertEqual(restoredInteractive.thread?.modifiedAt, originalModifiedAt)
        XCTAssertFalse(restoredInteractive.thread?.conversations.first(where: \.isMain)?.isUnread == true)
        XCTAssertEqual(
            restoredInteractive.thread?.conversations.first?.events.first(where: { $0.type == "tool_approval" })?.toolApprovalStatus,
            nil
        )
        XCTAssertEqual(
            restoredInteractive.thread?.conversations.first?.events.first(where: { $0.type == "tool_call" })?.content,
            nil
        )
        XCTAssertEqual(fixture.controllerRegistry.flushForTerminationCalls, 0)
        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, 0)
        XCTAssertTrue(fixture.notificationManager.handleEventCalls.isEmpty)
    }
}

private enum RecoverySaveTestError: Error, Equatable {
    case forcedFailure
}

@MainActor
private final class ScheduledTaskRecoverySaveProbe {
    private let failingCall: Int
    private(set) var saveCalls = 0

    init(failingCall: Int) {
        self.failingCall = failingCall
    }

    func save(_ context: ModelContext) throws {
        saveCalls += 1
        if saveCalls == failingCall {
            throw RecoverySaveTestError.forcedFailure
        }
        try context.save()
    }
}

@MainActor
final class RecordingRecoveryControllerRegistry: ConversationControllerRegistry {
    private(set) var flushForTerminationCalls = 0

    func makeViewLease(for conversation: Conversation) -> ConversationControllerLease {
        preconditionFailure("Recovery tests do not create live controllers")
    }

    func makeBackgroundLease(for conversation: Conversation) -> ConversationControllerLease {
        preconditionFailure("Recovery tests do not create live controllers")
    }

    func makeBackgroundLease(
        for conversation: Conversation,
        defersAutomaticSuspension: Bool
    ) -> ConversationControllerLease {
        preconditionFailure("Recovery tests do not create live controllers")
    }

    func controller(for key: ConversationControllerKey) -> ConversationViewModel? {
        nil
    }

    func outcomes(for key: ConversationControllerKey) -> AsyncStream<ConversationControllerOutcome> {
        AsyncStream { $0.finish() }
    }

    func flushForTermination() -> [ConversationControllerFlushFailure] {
        flushForTerminationCalls += 1
        return []
    }

    func invalidate(for key: ConversationControllerKey) {}

    func invalidateAll() {}
}
