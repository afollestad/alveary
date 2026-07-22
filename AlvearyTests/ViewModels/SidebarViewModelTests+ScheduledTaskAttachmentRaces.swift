import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchiveRejectsScheduleAttachedWhileWaitingForRunQuiescence() async throws {
        let gate = SidebarScheduledRunQuiescenceGate()
        let fixture = try SidebarTestFixture(
            stopAndWaitForScheduledTaskRun: { runID in
                await gate.stopAndWait(runID: runID)
            }
        )
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .preparing,
            conversationID: "scheduled-attachment-race-archive"
        )
        let threadID = thread.persistentModelID
        let runID = run.persistentModelID
        let archive = Task { @MainActor in
            try await fixture.viewModel.archiveThread(thread)
        }
        await gate.waitUntilEntered()
        let currentThread = try XCTUnwrap(fixture.context.resolveThread(id: threadID))
        let currentRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        try attachSchedule(title: "Late archive schedule", to: currentThread, fixture: fixture)
        currentRun.status = .interrupted
        currentRun.finishedAt = Date()
        try fixture.context.save()
        gate.release()

        do {
            try await archive.value
            XCTFail("Expected the late schedule attachment to prevent archiving")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "This thread is attached to the scheduled task \"Late archive schedule\". Remove or retarget that schedule first."
            )
        }
        XCTAssertNil(fixture.context.resolveThread(id: threadID)?.archivedAt)
    }

    func testDeleteRejectsScheduleAttachedWhileWaitingForRunQuiescence() async throws {
        let gate = SidebarScheduledRunQuiescenceGate()
        let fixture = try SidebarTestFixture(
            stopAndWaitForScheduledTaskRun: { runID in
                await gate.stopAndWait(runID: runID)
            }
        )
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .preparing,
            conversationID: "scheduled-attachment-race-delete"
        )
        let threadID = thread.persistentModelID
        let runID = run.persistentModelID
        let deletion = Task { @MainActor in
            try await fixture.viewModel.deleteThread(thread)
        }
        await gate.waitUntilEntered()
        let currentThread = try XCTUnwrap(fixture.context.resolveThread(id: threadID))
        let currentRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: runID))
        try attachSchedule(title: "Late delete schedule", to: currentThread, fixture: fixture)
        currentRun.status = .interrupted
        currentRun.finishedAt = Date()
        try fixture.context.save()
        gate.release()

        do {
            try await deletion.value
            XCTFail("Expected the late schedule attachment to prevent deletion")
        } catch {
            XCTAssertEqual(
                error.localizedDescription,
                "This thread is attached to the scheduled task \"Late delete schedule\". Remove or retarget that schedule first."
            )
        }
        XCTAssertNotNil(fixture.context.resolveThread(id: threadID))
    }

    func testPendingWorktreeCleanupRejectsNewAttachmentWhileDeletionIsInFlight() async throws {
        let completionGate = SidebarMockBranchDeletionGate()
        let fixture = try SidebarTestFixture(
            afterPendingScheduledWorktreeCleanup: {
                await completionGate.enterAndWaitForRelease()
            }
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("alveary-pending-cleanup-attachment-race-\(UUID().uuidString)", isDirectory: true)
        let sourceRoot = root.appendingPathComponent("Source", isDirectory: true)
        let worktreeRoot = root.appendingPathComponent("Worktree", isDirectory: true)
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let branch = "alveary/pending-cleanup-attachment-race"
        let thread = try insertPendingCleanupTarget(
            fixture: fixture,
            sourceRoot: sourceRoot,
            worktreeRoot: worktreeRoot,
            branch: branch
        )
        let threadID = thread.persistentModelID

        await fixture.worktreeManager.setListResult([
            WorktreeInfo(path: worktreeRoot.path, branch: branch, headOID: "owned-head")
        ])
        let deletion = Task { @MainActor in
            try await fixture.viewModel.deleteThread(thread)
        }
        await completionGate.waitUntilEntered()

        XCTAssertFalse(FileManager.default.fileExists(atPath: worktreeRoot.path))
        XCTAssertTrue(try XCTUnwrap(fixture.context.resolveThread(id: threadID)).hasPendingScheduledTaskWorktreeCleanup)

        let mutationService = ScheduledTaskMutationService(modelContext: fixture.context)
        XCTAssertThrowsError(
            try mutationService.create(
                edit: lateAttachmentEdit(targetThread: thread)
            )
        ) { error in
            XCTAssertEqual(error as? ScheduledTaskMutationError, .existingThreadRequiresPinnedThread)
        }

        await completionGate.release()
        try await deletion.value

        XCTAssertNil(fixture.context.resolveThread(id: threadID))
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ScheduledTask>()).isEmpty)
    }

    func testTerminalTargetRunAwaitingFinalizationStillDisablesLifecycleActions() async throws {
        let fixture = try SidebarTestFixture()
        let (target, _) = try insertTerminalTargetRun(
            fixture: fixture,
            requiresFinalizationRecovery: true,
            idSuffix: "awaiting-finalization"
        )
        let targetID = target.persistentModelID
        let expectedReason =
            "This thread has an active scheduled task run. Wait for it to finish before archiving, deleting, or unpinning this thread."

        XCTAssertEqual(fixture.viewModel.scheduledTaskAttachmentReason(for: target), expectedReason)
        XCTAssertThrowsError(try fixture.viewModel.setThreadPinned(target, isPinned: false)) { error in
            XCTAssertEqual(error.localizedDescription, expectedReason)
        }

        do {
            try await fixture.viewModel.archiveThread(target)
            XCTFail("Expected finalization recovery to prevent archiving")
        } catch {
            XCTAssertEqual(error.localizedDescription, expectedReason)
        }

        do {
            try await fixture.viewModel.deleteThread(target)
            XCTFail("Expected finalization recovery to prevent deletion")
        } catch {
            XCTAssertEqual(error.localizedDescription, expectedReason)
        }

        let persistedTarget = try XCTUnwrap(fixture.context.resolveThread(id: targetID))
        XCTAssertTrue(persistedTarget.isPinned)
        XCTAssertNil(persistedTarget.archivedAt)
    }

    func testTerminalTargetRunAllowsLifecycleActionsAfterFinalizationMarkerClears() throws {
        let fixture = try SidebarTestFixture()
        let (target, run) = try insertTerminalTargetRun(
            fixture: fixture,
            requiresFinalizationRecovery: false,
            idSuffix: "finalized"
        )

        XCTAssertTrue(run.hasKnownTerminalStatus)
        XCTAssertFalse(target.hasBlockingScheduledTaskRunAttachment)
        XCTAssertNil(fixture.viewModel.scheduledTaskAttachmentReason(for: target))
        XCTAssertNoThrow(try fixture.viewModel.requireNoScheduledTaskAttachment(target))
        XCTAssertNoThrow(try fixture.viewModel.setThreadPinned(target, isPinned: false))
        XCTAssertFalse(target.isPinned)
    }
}

@MainActor
private func insertTerminalTargetRun(
    fixture: SidebarTestFixture,
    requiresFinalizationRecovery: Bool,
    idSuffix: String
) throws -> (target: AgentThread, run: ScheduledTaskRun) {
    let target = AgentThread(name: "Terminal target run", isPinned: true, mode: .task)
    let run = ScheduledTaskRun(
        occurrenceID: "terminal-target-run-\(idSuffix)",
        definitionID: "terminal-target-definition-\(idSuffix)",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: .success,
        titleSnapshot: "Terminal target run",
        promptSnapshot: "Continue work.",
        destinationSnapshot: .existingThread,
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: .localCheckout,
        finishedAt: Date(timeIntervalSince1970: 1_800_000_100),
        requiresFinalizationRecovery: requiresFinalizationRecovery,
        targetThread: target
    )
    target.targetedScheduledTaskRuns = [run]
    fixture.context.insert(target)
    fixture.context.insert(run)
    try fixture.context.save()
    return (target, run)
}

@MainActor
private func attachSchedule(
    title: String,
    to thread: AgentThread,
    fixture: SidebarTestFixture
) throws {
    let definition = ScheduledTask(
        title: title,
        prompt: "Continue in the pinned task.",
        destination: .existingThread,
        recurrence: .daily(hour: 9, minute: 0),
        timeZoneIdentifier: "America/Chicago",
        providerID: "codex",
        targetThread: thread
    )
    fixture.context.insert(definition)
    try fixture.context.save()
}

@MainActor
private func insertPendingCleanupTarget(
    fixture: SidebarTestFixture,
    sourceRoot: URL,
    worktreeRoot: URL,
    branch: String
) throws -> AgentThread {
    let sourceIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: sourceRoot.path)
    let worktreeIdentity = try fixture.taskWorkspaceOwnershipService.directoryIdentity(at: worktreeRoot.path)
    let run = try makePendingCleanupRun(
        sourceRoot: sourceRoot,
        worktreeRoot: worktreeRoot,
        branch: branch,
        sourceIdentity: sourceIdentity,
        worktreeIdentity: worktreeIdentity
    )
    let thread = AgentThread(
        name: "Pending cleanup target",
        isPinned: true,
        mode: .task,
        scheduledTaskRun: run
    )
    thread.conversations = [
        Conversation(id: "pending-cleanup-target", provider: "codex", thread: thread)
    ]
    run.thread = thread
    fixture.context.insert(run)
    fixture.context.insert(thread)
    try fixture.context.save()
    return thread
}

@MainActor
private func makePendingCleanupRun(
    sourceRoot: URL,
    worktreeRoot: URL,
    branch: String,
    sourceIdentity: TaskWorkspaceFileSystemIdentity,
    worktreeIdentity: TaskWorkspaceFileSystemIdentity
) throws -> ScheduledTaskRun {
    let run = ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "pending-cleanup-definition",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: .failure,
        titleSnapshot: "Pending cleanup target",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .privateWorkspace,
        workspaceStrategySnapshot: .worktree
    )
    let cleanup = ScheduledWorktreeCleanupProvenance(
        sourceProjectPath: sourceRoot.path,
        worktreePath: worktreeRoot.path,
        branch: branch,
        sourceProjectIdentity: sourceIdentity,
        worktreeIdentity: worktreeIdentity,
        branchOID: "owned-head",
        ownershipMarkerID: nil,
        ownershipSourceProjectPath: nil
    )
    run.setPendingWorktreeCleanup(try XCTUnwrap(cleanup))
    return run
}

private func lateAttachmentEdit(targetThread: AgentThread) -> ScheduledTaskDefinitionEdit {
    ScheduledTaskDefinitionEdit(
        title: "Late attachment",
        prompt: "Continue in the pinned task.",
        destination: .existingThread,
        recurrence: .daily(hour: 9, minute: 0),
        timeZoneIdentifier: "America/Chicago",
        providerID: "codex",
        model: nil,
        effort: "high",
        permissionMode: "default",
        workspaceKind: .project,
        workspaceStrategy: .localCheckout,
        grantedRoots: [],
        project: nil,
        targetThread: targetThread
    )
}
