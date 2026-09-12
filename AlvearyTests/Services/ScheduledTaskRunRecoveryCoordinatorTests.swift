import Foundation
import SwiftData
import XCTest
@testable import Alveary

@MainActor
final class ScheduledTaskRunRecoveryCoordinatorTests: XCTestCase {
    func testRecoveryResumesOnlySafeFreshClaimsAndInterruptsOtherWork() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let resumable = fixture.insertRun(status: .claimed, occurrenceAt: now.addingTimeInterval(-60))
        let unsafe = fixture.insertRun(status: .claimed, occurrenceAt: now.addingTimeInterval(-120))
        let legacyWithoutIdentity = fixture.insertRun(
            status: .claimed,
            occurrenceAt: now.addingTimeInterval(-180)
        )
        legacyWithoutIdentity.workspaceIdentitySnapshot = nil
        let stale = fixture.insertRun(
            status: .claimed,
            occurrenceAt: now.addingTimeInterval(-(ScheduledTaskRecurrenceCalculator.defaultCatchUpAge + 1)),
            withThread: false
        )
        let running = fixture.insertRun(status: .running, occurrenceAt: now.addingTimeInterval(-300), withPendingApproval: true)
        let completed = fixture.insertRun(status: .success, occurrenceAt: now.addingTimeInterval(-400))
        try fixture.context.save()

        let result = try fixture.coordinator.recoverPersistedRuns(at: now) { run in
            run.persistentModelID == resumable.persistentModelID
        }

        XCTAssertEqual(result.resumedRunIDs, [resumable.persistentModelID])
        XCTAssertEqual(Set(result.interruptedRunIDs), Set([
            unsafe.persistentModelID,
            legacyWithoutIdentity.persistentModelID,
            stale.persistentModelID,
            running.persistentModelID
        ]))
        XCTAssertEqual(resumable.status, .claimed)
        XCTAssertEqual(unsafe.status, .interrupted)
        XCTAssertEqual(legacyWithoutIdentity.status, .interrupted)
        XCTAssertEqual(stale.status, .interrupted)
        XCTAssertEqual(running.status, .interrupted)
        XCTAssertEqual(completed.status, .success)
        assertInterruptedRunProvenance(stale: stale, running: running)
        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, 1)
    }

    func testTerminationPreparationPersistsInterruptionsBeforeReturningTargets() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let preparing = fixture.insertRun(status: .preparing, occurrenceAt: actionDate.addingTimeInterval(-30))
        let waiting = fixture.insertRun(
            status: .waiting,
            occurrenceAt: actionDate.addingTimeInterval(-20),
            withPendingApproval: true
        )
        let claimed = fixture.insertRun(status: .claimed, occurrenceAt: actionDate.addingTimeInterval(-10))
        try fixture.context.save()

        let result = try fixture.coordinator.prepareForTermination(at: actionDate)

        XCTAssertEqual(Set(result.interruptedRunIDs), Set([preparing.persistentModelID, waiting.persistentModelID]))
        XCTAssertEqual(Set(result.conversationIDsToTerminate), Set([
            try XCTUnwrap(preparing.thread?.conversations.first?.id),
            try XCTUnwrap(waiting.thread?.conversations.first?.id)
        ]))
        XCTAssertTrue(result.controllerFlushFailures.isEmpty)
        XCTAssertEqual(preparing.status, .interrupted)
        XCTAssertEqual(preparing.thread?.modifiedAt, actionDate)
        XCTAssertEqual(waiting.status, .interrupted)
        XCTAssertEqual(waiting.thread?.modifiedAt, actionDate)
        XCTAssertEqual(waiting.finishedAt, actionDate)
        XCTAssertEqual(waiting.thread?.conversations.first(where: \.isMain)?.isUnread, true)
        XCTAssertEqual(claimed.status, .claimed)
        XCTAssertEqual(
            waiting.thread?.conversations.first?.events.first(where: { $0.type == "tool_approval" })?.toolApprovalStatus,
            ToolApprovalStatus.superseded.rawValue
        )
        XCTAssertEqual(
            waiting.thread?.conversations.first?.events.first(where: { $0.type == "tool_call" })?.content,
            ChatItemGrouper.handledPromptSummary
        )
        XCTAssertEqual(fixture.notificationManager.refreshBadgeCountCalls, 1)
    }

    func testTerminationReconstructsPreparedWorkspaceDescriptorsForMissingTaskShells() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let privateRun = makePrivatePreparedRun(fixture: fixture, actionDate: actionDate)
        let worktreeRun = makeWorktreePreparedRun(fixture: fixture, actionDate: actionDate)
        let localRun = makeLocalPreparedRun(fixture: fixture, actionDate: actionDate)
        try fixture.context.save()

        _ = try fixture.coordinator.prepareForTermination(at: actionDate)

        assertRecoveredWorkspaces(
            privateRun: privateRun,
            worktreeRun: worktreeRun,
            localRun: localRun
        )
    }

    func testTerminationRejectsInvalidPreparedWorkspaceMetadata() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let run = fixture.insertRun(status: .preparing, occurrenceAt: actionDate, withThread: false)
        run.preparedWorkspaceRoot = "/tmp/private/cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        run.preparedWorkspaceOwnershipStrategy = .projectWorktreeOwned
        run.preparedWorkspaceMarkerID = "cccccccc-cccc-4ccc-8ccc-cccccccccccc"
        run.grantedRootsSnapshot = ["relative-grant"]
        try fixture.context.save()

        _ = try fixture.coordinator.prepareForTermination(at: actionDate)

        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
        XCTAssertNil(run.thread?.worktreePath)
        XCTAssertFalse(run.thread?.useWorktree == true)
    }

    func testRecoveryWithholdsExistingWorkspaceWhenGrantIdentityChanged() throws {
        let fixture = try ScheduledTaskRecoveryFixture()
        let actionDate = Date(timeIntervalSinceReferenceDate: 5_000_000)
        let markerID = "dddddddd-dddd-4ddd-8ddd-dddddddddddd"
        let ownedRoot = "/tmp/private/\(markerID)"
        let grantPath = "/tmp/replaced-grant"
        let claimedGrantIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 40)
        let replacementGrantIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 41)
        let run = fixture.insertRun(status: .running, occurrenceAt: actionDate)
        run.grantedRootsSnapshot = [grantPath]
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: nil,
            grantedRoots: [ScheduledTaskRootIdentitySnapshot(
                path: grantPath,
                identity: claimedGrantIdentity
            )]
        )
        run.preparedWorkspaceRoot = ownedRoot
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = markerID
        run.thread?.taskWorkspaceDescriptor = TaskWorkspaceDescriptor(
            primaryRoot: ownedRoot,
            grantedRoots: [grantPath],
            ownershipStrategy: .privateOwned,
            ownershipMarkerID: markerID
        )
        fixture.workspaceOwnershipService.setIdentity(replacementGrantIdentity, at: grantPath)
        try fixture.context.save()

        _ = try fixture.coordinator.recoverPersistedRuns(at: actionDate) { _ in false }

        XCTAssertEqual(run.status, .interrupted)
        XCTAssertNil(run.thread?.taskWorkspaceDescriptor)
        XCTAssertNil(run.thread?.worktreePath)
        XCTAssertFalse(run.thread?.useWorktree == true)
        XCTAssertEqual(run.preparedWorkspaceRoot, ownedRoot)
        XCTAssertEqual(run.preparedWorkspaceMarkerID, markerID)
    }

}

@MainActor
private extension ScheduledTaskRunRecoveryCoordinatorTests {
    func assertInterruptedRunProvenance(stale: ScheduledTaskRun, running: ScheduledTaskRun) {
        XCTAssertEqual(stale.thread?.mode, .task)
        XCTAssertEqual(stale.thread?.hasCustomName, true)
        XCTAssertEqual(stale.thread?.conversations.first(where: \.isMain)?.isUnread, true)
        XCTAssertEqual(
            stale.thread?.conversations.first(where: \.isMain)?.events.first {
                $0.type == ConversationEventRecord.scheduledTaskNoteType
            }?.content,
            "Scheduled task \"Scheduled task\" for Jan 5, 2001 at 7:46\u{202F}AM"
        )
        XCTAssertEqual(
            running.thread?.conversations.first?.events.first(where: { $0.type == "tool_approval" })?.toolApprovalStatus,
            ToolApprovalStatus.superseded.rawValue
        )
        XCTAssertEqual(
            running.thread?.conversations.first?.events.first(where: { $0.type == "tool_call" })?.content,
            ChatItemGrouper.handledPromptSummary
        )
    }

    func makePrivatePreparedRun(
        fixture: ScheduledTaskRecoveryFixture,
        actionDate: Date
    ) -> ScheduledTaskRun {
        let marker = "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
        let root = "/tmp/private/\(marker)"
        let run = fixture.insertRun(status: .preparing, occurrenceAt: actionDate, withThread: false)
        run.preparedWorkspaceRoot = root
        run.preparedWorkspaceOwnershipStrategy = .privateOwned
        run.preparedWorkspaceMarkerID = marker
        run.grantedRootsSnapshot = ["/tmp/private-grant"]
        let grantIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 10)
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: nil,
            grantedRoots: [ScheduledTaskRootIdentitySnapshot(
                path: "/tmp/private-grant",
                identity: grantIdentity
            )]
        )
        fixture.workspaceOwnershipService.setIdentity(grantIdentity, at: "/tmp/private-grant")
        fixture.workspaceOwnershipService.allow(TaskWorkspaceDescriptor(
            primaryRoot: root,
            grantedRoots: ["/tmp/private-grant"],
            ownershipStrategy: .privateOwned,
            ownershipMarkerID: marker
        ))
        run.workspaceSnapshot = WorkspaceSnapshot(
            primarySource: run.projectPathSnapshot.map { SourceFolderSnapshot(path: $0) },
            grants: run.grantedRootsSnapshot.map { SourceFolderSnapshot(path: $0) }
        )
        return run
    }

    func makeWorktreePreparedRun(
        fixture: ScheduledTaskRecoveryFixture,
        actionDate: Date
    ) -> ScheduledTaskRun {
        let marker = "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb"
        let run = fixture.insertRun(status: .running, occurrenceAt: actionDate, withThread: false)
        run.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.project.rawValue
        run.workspaceStrategyRawValueSnapshot = ScheduledTaskWorkspaceStrategy.worktree.rawValue
        run.projectPathSnapshot = "/tmp/source-project"
        run.grantedRootsSnapshot = ["/tmp/worktree-grant"]
        run.preparedWorkspaceRoot = "/tmp/worktrees/recovered"
        run.preparedWorkspaceOwnershipStrategy = .projectWorktreeOwned
        run.preparedWorkspaceMarkerID = marker
        let sourceIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 20)
        let grantIdentity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 21)
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: ScheduledTaskRootIdentitySnapshot(
                path: "/tmp/source-project",
                identity: sourceIdentity
            ),
            grantedRoots: [ScheduledTaskRootIdentitySnapshot(
                path: "/tmp/worktree-grant",
                identity: grantIdentity
            )]
        )
        fixture.workspaceOwnershipService.setIdentity(sourceIdentity, at: "/tmp/source-project")
        fixture.workspaceOwnershipService.setIdentity(grantIdentity, at: "/tmp/worktree-grant")
        fixture.workspaceOwnershipService.allow(TaskWorkspaceDescriptor(
            primaryRoot: "/tmp/worktrees/recovered",
            grantedRoots: ["/tmp/worktree-grant"],
            ownershipStrategy: .projectWorktreeOwned,
            ownershipMarkerID: marker,
            sourceProjectPath: "/tmp/source-project"
        ), sourceProjectIdentity: sourceIdentity)
        run.workspaceSnapshot = WorkspaceSnapshot(
            primarySource: run.projectPathSnapshot.map { SourceFolderSnapshot(path: $0) },
            grants: run.grantedRootsSnapshot.map { SourceFolderSnapshot(path: $0) }
        )
        return run
    }

    func makeLocalPreparedRun(
        fixture: ScheduledTaskRecoveryFixture,
        actionDate: Date
    ) -> ScheduledTaskRun {
        let run = fixture.insertRun(status: .waiting, occurrenceAt: actionDate, withThread: false)
        run.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.project.rawValue
        run.workspaceStrategyRawValueSnapshot = ScheduledTaskWorkspaceStrategy.localCheckout.rawValue
        run.projectPathSnapshot = "/tmp/local-project"
        run.preparedWorkspaceRoot = "/tmp/local-project"
        run.preparedWorkspaceOwnershipStrategy = .projectLocal
        let identity = TaskWorkspaceFileSystemIdentity(systemNumber: 1, fileNumber: 30)
        run.workspaceIdentitySnapshot = ScheduledTaskWorkspaceIdentitySnapshot(
            projectRoot: ScheduledTaskRootIdentitySnapshot(
                path: "/tmp/local-project",
                identity: identity
            ),
            grantedRoots: []
        )
        fixture.workspaceOwnershipService.setIdentity(identity, at: "/tmp/local-project")
        run.workspaceSnapshot = WorkspaceSnapshot(
            primarySource: run.projectPathSnapshot.map { SourceFolderSnapshot(path: $0) },
            grants: run.grantedRootsSnapshot.map { SourceFolderSnapshot(path: $0) }
        )
        return run
    }

    func assertRecoveredWorkspaces(
        privateRun: ScheduledTaskRun,
        worktreeRun: ScheduledTaskRun,
        localRun: ScheduledTaskRun
    ) {
        XCTAssertEqual(
            privateRun.thread?.taskWorkspaceDescriptor,
            TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/private/aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa",
                grantedRoots: ["/tmp/private-grant"],
                ownershipStrategy: .privateOwned,
                ownershipMarkerID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"
            )
        )
        XCTAssertFalse(privateRun.thread?.useWorktree == true)
        XCTAssertNil(privateRun.thread?.worktreePath)
        XCTAssertEqual(
            worktreeRun.thread?.resolvedWorkspaceDescriptor,
            TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/worktrees/recovered",
                grantedRoots: ["/tmp/worktree-grant"],
                ownershipStrategy: .projectWorktreeOwned,
                ownershipMarkerID: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb",
                sourceProjectPath: "/tmp/source-project"
            )
        )
        XCTAssertEqual(worktreeRun.thread?.worktreePath, CanonicalPath.normalize("/tmp/worktrees/recovered"))
        XCTAssertTrue(worktreeRun.thread?.useWorktree == true)
        XCTAssertEqual(
            localRun.thread?.resolvedWorkspaceDescriptor,
            TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/local-project",
                ownershipStrategy: .projectLocal,
                sourceProjectPath: "/tmp/local-project"
            )
        )
        XCTAssertNil(localRun.thread?.worktreePath)
        XCTAssertFalse(localRun.thread?.useWorktree == true)
    }
}
