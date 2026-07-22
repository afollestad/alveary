import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunRecoveryCoordinatorTests {
    func testExistingTargetRecoveryNotesAndSupersedesOnlyRunConversation() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 5_500_000)
        let claimedAt = actionDate.addingTimeInterval(-30)
        let target = AgentThread(name: "Pinned target", isPinned: true, mode: .task)
        let main = Conversation(id: "recovery-target-main", isMain: true, thread: target)
        let sibling = Conversation(id: "recovery-target-sibling", isMain: false, displayOrder: 1, thread: target)
        target.conversations = [main, sibling]
        let run = fixture.insertRun(status: .running, occurrenceAt: actionDate, withThread: false)
        run.destinationSnapshot = .existingThread
        run.targetConversationIDSnapshot = main.id
        run.targetThread = target
        run.startedAt = claimedAt.addingTimeInterval(0.5)
        let manualApproval = unresolvedApproval(
            conversation: main,
            id: "manual-approval",
            timestamp: claimedAt.addingTimeInterval(-1)
        )
        let note = ConversationEventRecord(
            id: "scheduled-task-\(run.id)",
            conversationId: main.id,
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: "Scheduled task note",
            timestamp: claimedAt,
            conversation: main
        )
        let scheduledApproval = unresolvedApproval(
            conversation: main,
            id: "scheduled-approval",
            timestamp: claimedAt.addingTimeInterval(1)
        )
        let siblingApproval = unresolvedApproval(
            conversation: sibling,
            id: "sibling-approval",
            timestamp: claimedAt.addingTimeInterval(1)
        )
        main.events = [manualApproval, note, scheduledApproval]
        sibling.events = [siblingApproval]
        fixture.context.insert(target)
        fixture.context.insert(main)
        fixture.context.insert(sibling)
        for record in [manualApproval, note, scheduledApproval, siblingApproval] {
            fixture.context.insert(record)
        }
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }
        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        let approvals = ExistingTargetRecoveryApprovals(manual: manualApproval, scheduled: scheduledApproval, sibling: siblingApproval)
        assertExistingTargetRecovery(
            fixture: fixture, run: run, conversations: (main, sibling),
            approvals: approvals, claimedAt: claimedAt)
    }

    func testExistingTargetRecoveryWithoutRunNotePreservesManualInteractions() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 5_600_000)
        let claimedAt = actionDate.addingTimeInterval(-30)
        let target = AgentThread(name: "Pinned target", isPinned: true, mode: .task)
        let main = Conversation(id: "recovery-target-missing-note", isMain: true, thread: target)
        target.conversations = [main]
        let run = fixture.insertRun(status: .claimed, occurrenceAt: actionDate, withThread: false)
        run.destinationSnapshot = .existingThread
        run.targetConversationIDSnapshot = main.id
        run.targetThread = target
        run.claimedAt = claimedAt
        let manualApproval = unresolvedApproval(
            conversation: main,
            id: "manual-approval",
            timestamp: claimedAt.addingTimeInterval(1)
        )
        let manualQuestion = ConversationEventRecord(
            conversationId: main.id,
            type: "tool_call",
            toolId: "manual-question",
            toolName: "AskUserQuestion",
            timestamp: claimedAt.addingTimeInterval(2),
            conversation: main
        )
        main.events = [manualApproval, manualQuestion]
        fixture.context.insert(target)
        fixture.context.insert(main)
        fixture.context.insert(manualApproval)
        fixture.context.insert(manualQuestion)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(manualApproval.toolApprovalStatus)
        XCTAssertNil(manualQuestion.content)
        let note = try XCTUnwrap(main.events.first { $0.id == "scheduled-task-\(run.id)" })
        XCTAssertGreaterThan(note.timestamp, manualQuestion.timestamp)
        XCTAssertTrue(fixture.controllerRegistry.supersededConversationIDs.isEmpty)
    }

    func testExistingTargetPreparingRecoveryPreservesInteractionsAfterMaterializedNote() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 5_700_000)
        let claimedAt = actionDate.addingTimeInterval(-30)
        let target = AgentThread(name: "Pinned target", isPinned: true, mode: .task)
        let main = Conversation(id: "recovery-target-preparing", isMain: true, thread: target)
        target.conversations = [main]
        let run = fixture.insertRun(status: .preparing, occurrenceAt: actionDate, withThread: false)
        run.destinationSnapshot = .existingThread
        run.targetConversationIDSnapshot = main.id
        run.targetThread = target
        run.claimedAt = claimedAt
        let note = ConversationEventRecord(
            id: "scheduled-task-\(run.id)",
            conversationId: main.id,
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: "Scheduled task note",
            timestamp: claimedAt,
            conversation: main
        )
        let manualApproval = unresolvedApproval(
            conversation: main,
            id: "manual-approval-after-note",
            timestamp: claimedAt.addingTimeInterval(1)
        )
        main.events = [note, manualApproval]
        fixture.context.insert(target)
        fixture.context.insert(main)
        fixture.context.insert(note)
        fixture.context.insert(manualApproval)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.startedAt)
        XCTAssertNil(manualApproval.toolApprovalStatus)
        XCTAssertTrue(fixture.controllerRegistry.supersededConversationIDs.isEmpty)
    }

    func testRecoveryInterruptsClaimWithUnknownDestinationWithoutCreatingTaskShell() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_550_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: now.addingTimeInterval(-30),
            withThread: false
        )
        run.destinationRawValueSnapshot = "future-destination"
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in true }

        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.thread)
        XCTAssertNil(run.decodedDestinationSnapshot)
    }

    func testRecoveryPreservesKnownTerminalRunWithUnknownDestination() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_575_000)
        let run = fixture.insertRun(status: .success, occurrenceAt: now.addingTimeInterval(-30))
        run.destinationRawValueSnapshot = "future-destination"
        run.requiresFinalizationRecovery = true
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in false }

        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertTrue(result.interruptedRunIDs.isEmpty)
        XCTAssertEqual(run.status, .success)
        XCTAssertFalse(run.requiresFinalizationRecovery)
        XCTAssertNil(run.lastError)
    }

    func testUnknownDestinationRecoveryReconcilesAllRetainedThreadRelationships() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_590_000)
        let run = fixture.insertRun(status: .claimed, occurrenceAt: now.addingTimeInterval(-30))
        let taskConversation = try XCTUnwrap(run.thread?.conversations.first)
        let target = AgentThread(name: "Retained target", isPinned: true)
        let targetMain = Conversation(id: "unknown-target-main", isMain: true, thread: target)
        let targetSibling = Conversation(id: "unknown-target-sibling", isMain: false, thread: target)
        target.conversations = [targetMain, targetSibling]
        run.targetConversationIDSnapshot = targetMain.id
        run.targetThread = target
        run.destinationRawValueSnapshot = "future-destination"
        fixture.context.insert(target)
        fixture.context.insert(targetMain)
        fixture.context.insert(targetSibling)
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in true }

        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertFalse(taskConversation.isUnread)
        XCTAssertFalse(targetMain.isUnread)
        XCTAssertFalse(targetSibling.isUnread)
        XCTAssertTrue(targetMain.events.allSatisfy { $0.type != ConversationEventRecord.scheduledTaskNoteType })
        XCTAssertEqual(
            Set(fixture.controllerRegistry.reconciledConversationIDs),
            Set([taskConversation.id, targetMain.id, targetSibling.id])
        )
    }

    func testInvalidExistingTargetPresentationStillReconcilesTargetSiblings() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_595_000)
        let target = AgentThread(name: "Invalid presentation target", isPinned: true)
        let main = Conversation(id: "invalid-presentation-main", isMain: true, thread: target)
        let sibling = Conversation(id: "invalid-presentation-sibling", isMain: false, thread: target)
        target.conversations = [main, sibling]
        let approval = unresolvedApproval(conversation: main, id: "invalid-presentation-approval")
        main.events = [approval]
        let run = fixture.insertRun(status: .running, occurrenceAt: now, withThread: false)
        run.destinationSnapshot = .existingThread
        run.targetConversationIDSnapshot = "missing-main"
        run.targetThread = target
        fixture.context.insert(target)
        fixture.context.insert(main)
        fixture.context.insert(sibling)
        fixture.context.insert(approval)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertFalse(main.isUnread)
        XCTAssertFalse(sibling.isUnread)
        XCTAssertNil(approval.toolApprovalStatus)
        XCTAssertTrue(main.events.allSatisfy { $0.type != ConversationEventRecord.scheduledTaskNoteType })
        XCTAssertTrue(fixture.controllerRegistry.supersededConversationIDs.isEmpty)
        XCTAssertEqual(Set(fixture.controllerRegistry.reconciledConversationIDs), Set([main.id, sibling.id]))
    }

    func testRecoveryReconstructsProjectShellWithSnapshottedFolderGrant() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_597_500)
        let projectPath = "/tmp/recovered-project"
        let grantPath = "/tmp/recovered-project-grant"
        let project = Project(path: projectPath, name: "Recovered project")
        fixture.context.insert(project)
        let run = fixture.insertRun(status: .running, occurrenceAt: now, withThread: false)
        run.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.project.rawValue
        run.workspaceStrategyRawValueSnapshot = ScheduledTaskWorkspaceStrategy.localCheckout.rawValue
        run.projectPathSnapshot = projectPath
        run.grantedRootsSnapshot = [grantPath]
        run.preparedWorkspaceRoot = projectPath
        run.preparedWorkspaceOwnershipStrategy = .projectLocal
        let projectIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 2, fileNumber: 40)
        let grantIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 2, fileNumber: 41)
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: ScheduledTaskRootIdentitySnapshot(path: projectPath, identity: projectIdentity),
            grantedRoots: [ScheduledTaskRootIdentitySnapshot(path: grantPath, identity: grantIdentity)]
        )
        fixture.workspaceOwnershipService.setIdentity(projectIdentity, at: projectPath)
        fixture.workspaceOwnershipService.setIdentity(grantIdentity, at: grantPath)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in false }

        let thread = try XCTUnwrap(run.thread)
        XCTAssertEqual(thread.mode, .project)
        XCTAssertEqual(thread.project?.persistentModelID, project.persistentModelID)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
        XCTAssertEqual(thread.taskGrantedRoots, [CanonicalPath.normalize(grantPath)])
    }

    func testRecoveryAgesRunNowClaimFromFreshTriggerInsteadOfStaleOccurrence() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_500_000)
        let staleOccurrence = now.addingTimeInterval(
            -(ScheduledTaskRecurrenceCalculator.defaultCatchUpAge + 1)
        )
        let runNow = fixture.insertRun(
            status: .claimed,
            occurrenceAt: staleOccurrence,
            withThread: false
        )
        runNow.triggerKind = .runNow
        runNow.triggeredAt = now.addingTimeInterval(-30)
        let scheduled = fixture.insertRun(
            status: .claimed,
            occurrenceAt: staleOccurrence,
            withThread: false
        )
        scheduled.triggeredAt = now.addingTimeInterval(-30)
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in true }

        XCTAssertEqual(Set(result.resumedRunIDs), Set([runNow.persistentModelID]))
        XCTAssertEqual(Set(result.interruptedRunIDs), Set([scheduled.persistentModelID]))
        XCTAssertEqual(runNow.status, .claimed)
        XCTAssertEqual(scheduled.status, .interrupted)
    }

    func testRecoveryInterruptsClaimWithUnknownTriggerKind() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_600_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: now.addingTimeInterval(-30),
            withThread: false
        )
        run.triggerKindRawValue = "future-trigger"
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in true }

        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
    }

    func testRecoveryInterruptsRunWithUnknownStatusWithoutEvaluatingResumeSafety() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_700_000)
        let run = fixture.insertRun(
            status: .claimed,
            occurrenceAt: now.addingTimeInterval(-30),
            withThread: false
        )
        run.statusRawValue = "future-status"
        try fixture.context.save()
        var didEvaluateResumeSafety = false

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { _ in
            didEvaluateResumeSafety = true
            return true
        }

        XCTAssertFalse(didEvaluateResumeSafety)
        XCTAssertTrue(result.resumedRunIDs.isEmpty)
        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertEqual(run.finishedAt, now)
        XCTAssertEqual(run.lastError, "The scheduled task run has an invalid persisted status.")
    }

    func testTerminationInterruptsRunWithUnknownStatus() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_800_000)
        let run = fixture.insertRun(status: .success, occurrenceAt: now.addingTimeInterval(-30))
        run.statusRawValue = "future-status"
        try fixture.context.save()

        let result = try fixture.coordinator.prepareForTermination(at: now)

        XCTAssertEqual(result.interruptedRunIDs, [run.persistentModelID])
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertEqual(run.finishedAt, now)
    }
}

@MainActor
private extension ScheduledTaskRunRecoveryCoordinatorTests {
    func assertExistingTargetRecovery(
        fixture: ScheduledTaskRecoveryFixture,
        run: ScheduledTaskRun,
        conversations: (main: Conversation, sibling: Conversation),
        approvals: ExistingTargetRecoveryApprovals,
        claimedAt: Date
    ) {
        XCTAssertEqual(run.status, .interrupted)
        XCTAssertTrue(conversations.main.isUnread)
        XCTAssertFalse(conversations.sibling.isUnread)
        XCTAssertNil(approvals.manual.toolApprovalStatus)
        XCTAssertEqual(approvals.scheduled.toolApprovalStatus, ToolApprovalStatus.superseded.rawValue)
        XCTAssertNil(approvals.sibling.toolApprovalStatus)
        let notes = conversations.main.events.filter {
            $0.type == ConversationEventRecord.scheduledTaskNoteType
        }
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.timestamp, claimedAt)
        XCTAssertTrue(conversations.sibling.events.allSatisfy {
            $0.type != ConversationEventRecord.scheduledTaskNoteType
        })
        XCTAssertEqual(fixture.controllerRegistry.supersededConversationIDs, [conversations.main.id])
        XCTAssertEqual(
            fixture.controllerRegistry.supersededInteractionIDsByConversationID[conversations.main.id],
            ["scheduled-approval"]
        )
        XCTAssertEqual(
            Set(fixture.controllerRegistry.reconciledConversationIDs),
            Set([conversations.main.id, conversations.sibling.id])
        )
    }

    func unresolvedApproval(
        conversation: Conversation,
        id: String,
        timestamp: Date = .now
    ) -> ConversationEventRecord {
        ConversationEventRecord(
            conversationId: conversation.id,
            type: "tool_approval",
            toolId: id,
            toolName: "Bash",
            timestamp: timestamp,
            conversation: conversation
        )
    }
}

private struct ExistingTargetRecoveryApprovals {
    let manual: ConversationEventRecord
    let scheduled: ConversationEventRecord
    let sibling: ConversationEventRecord
}
