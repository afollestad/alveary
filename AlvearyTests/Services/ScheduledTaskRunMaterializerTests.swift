import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ScheduledTaskRunMaterializerTests: XCTestCase {
    func testPrivateOccurrenceCreatesSeparateProjectlessTaskWithProvenanceAndLocalizedNote() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let grant = try fixture.createDirectory(named: "Grant")
        let occurrence = try XCTUnwrap(fixture.gregorianDate(
            year: 2027,
            month: 1,
            day: 15,
            hour: 15,
            minute: 30
        ))
        let firstRun = try fixture.insertRun(
            id: "first-run",
            occurrenceID: "first-occurrence",
            occurrenceAt: occurrence,
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree,
            grantedRoots: [grant.path]
        )
        let secondRun = try fixture.insertRun(
            id: "second-run",
            occurrenceID: "second-occurrence",
            occurrenceAt: occurrence.addingTimeInterval(60),
            workspaceKind: .privateWorkspace,
            workspaceStrategy: .worktree
        )
        let fixedNow = Date(timeIntervalSince1970: 1_800_000_100)
        let materializer = fixture.makeMaterializer(now: fixedNow)

        let first = try await materializer.materialize(runID: firstRun.persistentModelID)
        let second = try await materializer.materialize(runID: secondRun.persistentModelID)

        try assertPrivateMaterializations(
            fixture: fixture,
            first: first,
            second: second,
            fixedNow: fixedNow,
            grant: grant
        )
    }

    private func assertPrivateMaterializations(
        fixture: ScheduledTaskRunMaterializerFixture,
        first: ScheduledTaskRunMaterialization,
        second: ScheduledTaskRunMaterialization,
        fixedNow: Date,
        grant: URL
    ) throws {

        let runs = try fixture.context.fetch(FetchDescriptor<ScheduledTaskRun>())
        let threads = try fixture.context.fetch(FetchDescriptor<AgentThread>())
        XCTAssertEqual(runs.map(\.status), [.preparing, .preparing])
        XCTAssertEqual(runs.map(\.preparationStartedAt), [fixedNow, fixedNow])
        XCTAssertEqual(threads.count, 2)
        XCTAssertEqual(Set(threads.map(\.mode)), [.task])
        XCTAssertTrue(threads.allSatisfy { $0.project == nil })
        XCTAssertTrue(threads.allSatisfy(\.hasCustomName))
        XCTAssertEqual(Set(threads.map(\.name)), ["Review changes"])
        XCTAssertNotEqual(first.threadID, second.threadID)
        XCTAssertNotEqual(first.conversationID, second.conversationID)
        XCTAssertNotEqual(first.workspace.primaryRoot, second.workspace.primaryRoot)
        XCTAssertEqual(first.prompt, "Review the scheduled changes.")
        XCTAssertEqual(first.workspace.grantedRoots, [CanonicalPath.normalize(grant.path)])

        let persistedFirst = try XCTUnwrap(runs.first { $0.id == "first-run" })
        let firstThread = try XCTUnwrap(persistedFirst.thread)
        XCTAssertEqual(firstThread.scheduledTaskRun?.id, persistedFirst.id)
        XCTAssertEqual(firstThread.permissionMode, "acceptEdits")
        XCTAssertEqual(firstThread.effort, "high")
        XCTAssertEqual(firstThread.model, "gpt-5")
        XCTAssertFalse(firstThread.useWorktree)
        XCTAssertEqual(persistedFirst.preparedWorkspaceRoot, first.workspace.primaryRoot)
        XCTAssertEqual(persistedFirst.preparedWorkspaceOwnershipStrategy, .privateOwned)
        XCTAssertEqual(persistedFirst.preparedWorkspaceMarkerID, first.workspace.ownershipMarkerID)

        let conversation = try XCTUnwrap(firstThread.conversations.first)
        XCTAssertEqual(conversation.provider, "codex")
        try assertScheduledNote(conversation: conversation, fixedNow: fixedNow)
    }

    private func assertScheduledNote(conversation: Conversation, fixedNow: Date) throws {
        let note = try XCTUnwrap(conversation.events.first)
        XCTAssertEqual(note.type, ConversationEventRecord.scheduledTaskNoteType)
        XCTAssertEqual(note.content, "Scheduled task for Jan 15, 2027 at 9:30\u{202F}AM")
        XCTAssertEqual(note.timestamp, fixedNow)
        XCTAssertEqual(conversation.restoreContextFromHistory(), nil)

        let grouper = ChatItemGrouper()
        grouper.update(events: [note])
        XCTAssertEqual(
            grouper.items,
            [.transcriptNote(id: note.id, kind: .scheduledTask(try XCTUnwrap(note.content)))]
        )
        XCTAssertEqual(TranscriptNoteKind.scheduledTask(try XCTUnwrap(note.content)).alignment, .centered)
    }

    func testProjectLocalOccurrenceUsesSnapshotPathWithoutAttachingProject() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "Project")
        let grant = try fixture.createDirectory(named: "Grant")
        let project = Project(path: projectRoot.path, name: "Source")
        fixture.context.insert(project)
        let run = try fixture.insertRun(
            id: "local-run",
            occurrenceID: "local-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: projectRoot.path,
            grantedRoots: [grant.path]
        )

        let result = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)

        let thread = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.thread)
        XCTAssertNil(thread.project)
        XCTAssertEqual(thread.mode, .task)
        XCTAssertFalse(thread.useWorktree)
        XCTAssertNil(thread.worktreePath)
        XCTAssertEqual(result.workspace.ownershipStrategy, .projectLocal)
        XCTAssertEqual(result.workspace.primaryRoot, CanonicalPath.normalize(projectRoot.path))
        XCTAssertEqual(result.workspace.sourceProjectPath, CanonicalPath.normalize(projectRoot.path))
        XCTAssertEqual(result.workspace.grantedRoots, [CanonicalPath.normalize(grant.path)])
        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(createCalls.isEmpty)
    }

    func testProjectWorktreeOccurrenceCreatesAndRegistersFreshOwnedWorktree() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "Project")
        let worktreeRoot = try fixture.createDirectory(named: "Worktree")
        let grant = try fixture.createDirectory(named: "Grant")
        let project = Project(
            path: projectRoot.path,
            name: "Source",
            remoteName: "upstream",
            baseRef: "main"
        )
        fixture.context.insert(project)
        try fixture.context.save()
        await fixture.worktreeManager.setCreateResult(
            WorktreeInfo(path: worktreeRoot.path, branch: "alveary/scheduled-review")
        )
        let run = try fixture.insertRun(
            id: "worktree-run",
            occurrenceID: "worktree-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .worktree,
            projectPath: projectRoot.path,
            projectBaseRef: "main",
            projectRemoteName: "upstream",
            grantedRoots: [grant.path]
        )
        project.baseRef = "develop"
        project.remoteName = "origin"
        try fixture.context.save()

        let result = try await fixture.makeMaterializer().materialize(runID: run.persistentModelID)

        let thread = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.thread)
        XCTAssertNil(thread.project)
        XCTAssertTrue(thread.useWorktree)
        XCTAssertEqual(thread.branch, "alveary/scheduled-review")
        XCTAssertEqual(thread.worktreePath, CanonicalPath.normalize(worktreeRoot.path))
        XCTAssertEqual(result.workspace.ownershipStrategy, .projectWorktreeOwned)
        XCTAssertEqual(result.workspace.primaryRoot, CanonicalPath.normalize(worktreeRoot.path))
        XCTAssertEqual(result.workspace.sourceProjectPath, CanonicalPath.normalize(projectRoot.path))
        XCTAssertEqual(result.workspace.grantedRoots, [CanonicalPath.normalize(grant.path)])
        XCTAssertNotNil(result.workspace.ownershipMarkerID)
        try fixture.workspaceOwnershipService.validateOwnedWorkspace(result.workspace)
        XCTAssertNil(run.pendingWorktreeCleanup)
        await assertWorktreeCreationUsesSnapshot(
            fixture: fixture,
            projectPath: projectRoot.path
        )
    }

    func testPrivateWorkspaceIsRemovedWhenThreadPersistenceFails() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let run = try fixture.insertRun(id: "private-failure", occurrenceID: "private-failure-occurrence")
        let failureDate = Date(timeIntervalSince1970: 1_800_000_200)
        var saveCount = 0
        let materializer = fixture.makeMaterializer(now: failureDate, saveChanges: { context in
            saveCount += 1
            if saveCount == 2 {
                run.thread?.modifiedAt = .distantPast
                throw ScheduledMaterializerTestError.saveFailed
            }
            try context.save()
        })

        await XCTAssertThrowsErrorAsync {
            _ = try await materializer.materialize(runID: run.persistentModelID)
        }

        let persistedRun = try XCTUnwrap(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID))
        XCTAssertEqual(persistedRun.status, .failure)
        let thread = try XCTUnwrap(persistedRun.thread)
        XCTAssertEqual(thread.modifiedAt, failureDate)
        XCTAssertNil(thread.taskWorkspaceDescriptor)
        XCTAssertTrue(try XCTUnwrap(thread.conversations.first).isUnread)
        XCTAssertNil(persistedRun.preparedWorkspaceRoot)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<Conversation>()), 1)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<ConversationEventRecord>()), 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: fixture.privateWorkspacesRoot.path), [])
    }

    func testProjectLocalWorkspaceIsPreservedWhenThreadPersistenceFails() async throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let projectRoot = try fixture.createDirectory(named: "Project")
        let sentinel = projectRoot.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: sentinel)
        let run = try fixture.insertRun(
            id: "local-failure",
            occurrenceID: "local-failure-occurrence",
            workspaceKind: .project,
            workspaceStrategy: .localCheckout,
            projectPath: projectRoot.path
        )
        var saveCount = 0
        let materializer = fixture.makeMaterializer(saveChanges: { context in
            saveCount += 1
            if saveCount == 2 {
                throw ScheduledMaterializerTestError.saveFailed
            }
            try context.save()
        })

        await XCTAssertThrowsErrorAsync {
            _ = try await materializer.materialize(runID: run.persistentModelID)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: sentinel.path))
        XCTAssertEqual(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.status, .failure)
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertNil(fixture.context.resolveScheduledTaskRun(id: run.persistentModelID)?.thread?.taskWorkspaceDescriptor)
    }

    func testScheduledNoteIsExplicitlyExcludedFromRestoreAndForkHistory() throws {
        let fixture = try ScheduledTaskRunMaterializerFixture()
        defer { fixture.removeFiles() }
        let conversation = Conversation(provider: "codex")
        let message = ConversationEventRecord(
            conversationId: conversation.id,
            type: "message",
            role: "user",
            content: "Continue the real work",
            conversation: conversation
        )
        let note = ConversationEventRecord(
            conversationId: conversation.id,
            type: ConversationEventRecord.scheduledTaskNoteType,
            content: "Scheduled task for Jan 15, 2027 at 9:30 AM",
            conversation: conversation
        )

        let restore = try XCTUnwrap(conversation.restoreContext(from: [message, note]))
        XCTAssertTrue(restore.contains("Continue the real work"))
        XCTAssertFalse(restore.contains("Scheduled task for"))

        XCTAssertFalse(ConversationForkTranscriptPolicy.shouldCopy(note))
    }
}

@MainActor
private func assertWorktreeCreationUsesSnapshot(
    fixture: ScheduledTaskRunMaterializerFixture,
    projectPath: String
) async {
    let createCalls = await fixture.worktreeManager.createCalls()
    XCTAssertEqual(
        createCalls,
        [.init(
            projectPath: CanonicalPath.normalize(projectPath),
            threadName: "Review changes",
            baseRef: "main",
            remoteName: "upstream"
        )]
    )
}

@MainActor
func XCTAssertThrowsErrorAsync(
    _ expression: @MainActor () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected expression to throw", file: file, line: line)
    } catch {
        // Expected.
    }
}
