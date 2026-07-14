import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ScheduledTaskRunMaterializerTests {
    func testMalformedWorkspaceKindFailsBeforePrivateWorkspacePreparation() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let run = try fixture.insertRun(
            id: "malformed-workspace-kind",
            occurrenceID: "malformed-workspace-kind-occurrence"
        )
        run.workspaceKindRawValueSnapshot = "malformed-kind"
        try fixture.context.save()

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertNotNil(persistedRun.thread)
        XCTAssertNil(persistedRun.thread?.taskWorkspaceDescriptor)
        XCTAssertEqual(persistedRun.lastError, "The scheduled task uses an invalid workspace configuration: malformed-kind/worktree.")
        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(createCalls.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.privateWorkspacesRoot.path))
    }

    func testMalformedWorkspaceStrategyFailsBeforeWorktreePreparation() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "MalformedStrategyProject")
        let run = try fixture.insertRun(
            id: "malformed-workspace-strategy",
            occurrenceID: "malformed-workspace-strategy-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: projectRoot.path
        )
        run.workspaceStrategyRawValueSnapshot = "malformed-strategy"
        try fixture.context.save()

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertNotNil(persistedRun.thread)
        XCTAssertNil(persistedRun.thread?.taskWorkspaceDescriptor)
        XCTAssertEqual(
            persistedRun.lastError,
            "The scheduled task uses an invalid workspace configuration: project/malformed-strategy."
        )
        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testPrivateGrantSymlinkSwapPersistsFailedTaskAndRemovesPreparedWorkspace() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let grant = try fixture.createDirectory(named: "Grant")
        let replacement = try fixture.createDirectory(named: "ReplacementGrant")
        let run = try fixture.insertRun(
            id: "private-grant-swap",
            occurrenceID: "private-grant-swap-occurrence",
            grantedRoots: [grant.path]
        )
        try FileManager.default.removeItem(at: grant)
        try FileManager.default.createSymbolicLink(atPath: grant.path, withDestinationPath: replacement.path)

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let thread = try XCTUnwrap(persistedRun.thread)
        let conversation = try XCTUnwrap(thread.conversations.first)
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(persistedRun.lastError, ScheduledTaskRunMaterializationError.workspaceRootsChanged.localizedDescription)
        XCTAssertEqual(thread.mode, .task)
        XCTAssertNil(thread.project)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
        XCTAssertTrue(thread.hasCustomName)
        XCTAssertTrue(conversation.isMain)
        XCTAssertTrue(conversation.isUnread)
        XCTAssertEqual(conversation.events.first?.type, ConversationEventRecord.scheduledTaskNoteType)
        XCTAssertEqual(fixture.failureNotifications.messages, [persistedRun.lastError])
        XCTAssertEqual(fixture.failureNotifications.conversationIDs, [conversation.id])
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.privateWorkspacesRoot.path), [])
    }

    func testPrivateGrantSamePathReplacementPersistsFailureAndRemovesPreparedWorkspace() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let grant = try fixture.createDirectory(named: "GrantToReplace")
        let run = try fixture.insertRun(
            id: "private-grant-replacement",
            occurrenceID: "private-grant-replacement-occurrence",
            grantedRoots: [grant.path]
        )
        try FileManager.default.removeItem(at: grant)
        try FileManager.default.createDirectory(at: grant, withIntermediateDirectories: true)
        let sentinel = grant.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(persistedRun.lastError, ScheduledTaskRunMaterializationError.workspaceRootsChanged.localizedDescription)
        XCTAssertNil(persistedRun.thread?.taskWorkspaceDescriptor)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.privateWorkspacesRoot.path), [])
    }

    func testProjectPrimaryRootSymlinkSwapIsRejectedBeforeUsingReplacement() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "ProjectToSwap")
        let replacement = try fixture.createDirectory(named: "ReplacementProject")
        let sentinel = replacement.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let run = try fixture.insertRun(
            id: "project-root-swap",
            occurrenceID: "project-root-swap-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: projectRoot.path
        )
        try FileManager.default.removeItem(at: projectRoot)
        try FileManager.default.createSymbolicLink(atPath: projectRoot.path, withDestinationPath: replacement.path)

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(persistedRun.lastError, ScheduledTaskRunMaterializationError.workspaceRootsChanged.localizedDescription)
        XCTAssertNotNil(persistedRun.thread)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testProjectLocalSamePathReplacementIsRejectedBeforeUsingReplacement() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "ProjectToReplace")
        let run = try fixture.insertRun(
            id: "project-root-replacement",
            occurrenceID: "project-root-replacement-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: projectRoot.path
        )
        try FileManager.default.removeItem(at: projectRoot)
        try FileManager.default.createDirectory(at: projectRoot, withIntermediateDirectories: true)
        let sentinel = projectRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(persistedRun.lastError, ScheduledTaskRunMaterializationError.workspaceRootsChanged.localizedDescription)
        XCTAssertNil(persistedRun.thread?.taskWorkspaceDescriptor)
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testWorktreePreparationFailurePersistsUnreadTaskAndRoutesError() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "FailingProject")
        await fixture.worktreeManager.setCreateError(ScheduledMaterializerTestError.worktreeCreateFailed)
        let run = try fixture.insertRun(
            id: "worktree-preparation-failure",
            occurrenceID: "worktree-preparation-failure-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let thread = try XCTUnwrap(persistedRun.thread)
        let conversation = try XCTUnwrap(thread.conversations.first)
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(persistedRun.lastError, ScheduledMaterializerTestError.worktreeCreateFailed.localizedDescription)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
        XCTAssertTrue(conversation.isUnread)
        XCTAssertEqual(conversation.events.first?.type, ConversationEventRecord.scheduledTaskNoteType)
        XCTAssertEqual(fixture.failureNotifications.messages, [persistedRun.lastError])
        XCTAssertEqual(fixture.failureNotifications.conversationIDs, [conversation.id])
    }

    func testWorktreePreparationCancellationKeepsDurablePreparingTaskForInterruption() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "CancelledProject")
        await fixture.worktreeManager.setCreateError(CancellationError())
        let run = try fixture.insertRun(
            id: "worktree-preparation-cancelled",
            occurrenceID: "worktree-preparation-cancelled-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )

        do {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let thread = try XCTUnwrap(persistedRun.thread)
        let conversation = try XCTUnwrap(thread.conversations.first)
        XCTAssertEqual(persistedRun.status, .preparing)
        XCTAssertNil(persistedRun.finishedAt)
        XCTAssertNil(persistedRun.lastError)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
        XCTAssertFalse(conversation.isUnread)
        XCTAssertTrue(fixture.failureNotifications.messages.isEmpty)
    }

    func testTaskShellPersistenceFailureLeavesRunClaimedForRecovery() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let run = try fixture.insertRun(
            id: "shell-persistence-failure",
            occurrenceID: "shell-persistence-failure-occurrence"
        )
        let materializer = fixture.makeMaterializer(
            saveChanges: { _ in throw ScheduledMaterializerTestError.saveFailed },
            provenancePersistenceAttempts: 2
        )

        do {
            _ = try await materializer.materialize(runID: run.persistentModelID)
            XCTFail("Expected provenance persistence failure")
        } catch let error as ScheduledTaskRunMaterializationError {
            guard case .provenancePersistenceFailed = error else {
                return XCTFail("Expected provenance persistence failure, got \(error)")
            }
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .claimed)
        XCTAssertNil(persistedRun.preparationStartedAt)
        XCTAssertNil(persistedRun.thread)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 0)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ConversationEventRecord>()), 0)
    }

    func testPrivateCancellationCleanupFailurePersistsCombinedFailure() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let ownershipService = ScheduledMaterializerOwnershipService(
            base: fixture.workspaceOwnershipService,
            cancelAfterPrivateWorkspaceCreation: true,
            removalError: ScheduledMaterializerTestError.cleanupFailed
        )
        let run = try fixture.insertRun(
            id: "private-cancellation-cleanup-failure",
            occurrenceID: "private-cancellation-cleanup-failure-occurrence"
        )
        let materializer = fixture.makeMaterializer(ownershipService: ownershipService)

        do {
            _ = try await Task { @MainActor in
                try await materializer.materialize(runID: run.persistentModelID)
            }.value
            XCTFail("Expected combined preparation and cleanup failure")
        } catch let error as ScheduledTaskRunMaterializationError {
            guard case .preparationAndCleanupFailed = error else {
                return XCTFail("Expected combined failure, got \(error)")
            }
        }

        try assertDurableCleanupFailure(fixture: fixture, runID: run.persistentModelID)
        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let workspace = try XCTUnwrap(persistedRun.thread?.taskWorkspaceDescriptor)
        XCTAssertEqual(workspace.ownershipStrategy, .privateOwned)
        XCTAssertEqual(persistedRun.preparedWorkspaceRoot, workspace.primaryRoot)
        XCTAssertEqual(persistedRun.preparedWorkspaceMarkerID, workspace.ownershipMarkerID)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.primaryRoot))
    }

    func testWorktreeCancellationCleanupFailurePersistsCombinedFailure() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "CancelledCleanupProject")
        let worktreeRoot = try fixture.createDirectory(named: "CancelledCleanupWorktree")
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/cancelled-cleanup")
        )
        await fixture.worktreeManager.setListResult([
            WorktreeInfo(
                path: worktreeRoot.path,
                branch: "alveary/cancelled-cleanup",
                headOID: "advanced-head"
            )
        ])
        await fixture.worktreeManager.setCancelAfterCreate(true)
        await fixture.worktreeManager.setRemoveError(ScheduledMaterializerTestError.cleanupFailed)
        let run = try fixture.insertRun(
            id: "worktree-cancellation-cleanup-failure",
            occurrenceID: "worktree-cancellation-cleanup-failure-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )

        do {
            _ = try await Task { @MainActor in
                try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
            }.value
            XCTFail("Expected combined preparation and cleanup failure")
        } catch let error as ScheduledTaskRunMaterializationError {
            guard case .preparationAndCleanupFailed = error else {
                return XCTFail("Expected combined failure, got \(error)")
            }
        }

        try assertDurableCleanupFailure(fixture: fixture, runID: run.persistentModelID)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let pendingCleanup = try XCTUnwrap(persistedRun.pendingWorktreeCleanup)
        XCTAssertEqual(pendingCleanup.sourceProjectPath, projectRoot.path)
        XCTAssertEqual(pendingCleanup.worktreePath, worktreeRoot.path)
        XCTAssertEqual(pendingCleanup.branch, "alveary/cancelled-cleanup")
        XCTAssertEqual(pendingCleanup.branchOID, "advanced-head")
        XCTAssertNil(pendingCleanup.ownedWorkspaceDescriptor)
    }

    func testWorktreeSourceSymlinkSwapAfterCreateIsRejectedAndPreservedForSafeCleanup() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "SourceProjectToSwap")
        let replacement = try fixture.createDirectory(named: "ReplacementSourceProject")
        let worktreeRoot = try fixture.createDirectory(named: "SourceSwapWorktree")
        let sentinel = replacement.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/source-swap")
        )
        let projectPath = projectRoot.path
        let replacementPath = replacement.path
        await fixture.worktreeManager.setCreateHook {
            try? FileManager.default.removeItem(atPath: projectPath)
            try? FileManager.default.createSymbolicLink(
                atPath: projectPath,
                withDestinationPath: replacementPath
            )
        }
        let run = try fixture.insertRun(
            id: "worktree-source-swap",
            occurrenceID: "worktree-source-swap-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectPath
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertTrue(try XCTUnwrap(persistedRun.lastError).contains("workspace cleanup also failed"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        let pendingCleanup = try XCTUnwrap(persistedRun.pendingWorktreeCleanup)
        XCTAssertEqual(pendingCleanup.sourceProjectPath, projectPath)
        XCTAssertEqual(pendingCleanup.worktreePath, worktreeRoot.path)
        XCTAssertEqual(pendingCleanup.branch, "alveary/source-swap")
        XCTAssertNil(pendingCleanup.ownedWorkspaceDescriptor)
        XCTAssertNil(pendingCleanup.worktreeIdentity)
        XCTAssertTrue(pendingCleanup.branchIsOwned)
        let removeCalls = await fixture.worktreeManager.removeCalls()
        XCTAssertTrue(removeCalls.isEmpty)
    }

    func testWorktreeSourceSamePathReplacementIsRejectedWithoutGitCleanup() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "SourceProjectToReplace")
        let worktreeRoot = try fixture.createDirectory(named: "SourceReplacementWorktree")
        let originalIdentity = try fixture.workspaceOwnershipService.directoryIdentity(at: projectRoot.path)
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/source-replacement")
        )
        let projectPath = projectRoot.path
        await fixture.worktreeManager.setCreateHook {
            try? FileManager.default.removeItem(atPath: projectPath)
            try? FileManager.default.createDirectory(
                atPath: projectPath,
                withIntermediateDirectories: true
            )
        }
        let run = try fixture.insertRun(
            id: "worktree-source-replacement",
            occurrenceID: "worktree-source-replacement-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectPath
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let pendingCleanup = try XCTUnwrap(persistedRun.pendingWorktreeCleanup)
        XCTAssertEqual(persistedRun.status, .failure)
        XCTAssertEqual(pendingCleanup.sourceProjectIdentity, originalIdentity)
        XCTAssertNil(pendingCleanup.ownedWorkspaceDescriptor)
        XCTAssertNil(pendingCleanup.worktreeIdentity)
        XCTAssertTrue(pendingCleanup.branchIsOwned)
        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        let removeCalls = await fixture.worktreeManager.removeCalls()
        XCTAssertTrue(removeCalls.isEmpty)
    }

    func testExhaustedFailureStateSavesDoNotNotifyBeforeCoordinatorPersistence() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "FailureSaveProject")
        await fixture.worktreeManager.setCreateError(ScheduledMaterializerTestError.worktreeCreateFailed)
        let run = try fixture.insertRun(
            id: "failure-state-save-exhaustion",
            occurrenceID: "failure-state-save-exhaustion-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path
        )
        var saveCount = 0
        let materializer = fixture.makeMaterializer(
            saveChanges: { context in
                saveCount += 1
                if saveCount > 1 {
                    throw ScheduledMaterializerTestError.saveFailed
                }
                try context.save()
            },
            provenancePersistenceAttempts: 2
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await materializer.materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        let conversation = try XCTUnwrap(persistedRun.thread?.conversations.first)
        XCTAssertEqual(persistedRun.status, .preparing)
        XCTAssertNil(persistedRun.finishedAt)
        XCTAssertNil(persistedRun.lastError)
        XCTAssertTrue(conversation.isUnread)
        XCTAssertTrue(fixture.failureNotifications.messages.isEmpty)
        XCTAssertTrue(fixture.failureNotifications.conversationIDs.isEmpty)
    }

    private func assertDurableCleanupFailure(
        fixture: ScheduledTaskRunMaterializerFixture,
        runID: PersistentIdentifier
    ) throws {
        let run = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        let conversation = try XCTUnwrap(run.thread?.conversations.first)
        XCTAssertEqual(run.status, .failure)
        XCTAssertTrue(try XCTUnwrap(run.lastError).contains("workspace cleanup also failed"))
        XCTAssertTrue(conversation.isUnread)
        XCTAssertEqual(fixture.failureNotifications.messages, [run.lastError])
        XCTAssertEqual(fixture.failureNotifications.conversationIDs, [conversation.id])
    }

}
