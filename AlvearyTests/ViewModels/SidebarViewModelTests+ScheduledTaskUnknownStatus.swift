import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testArchiveProjectModeThreadQuiescesLinkedScheduledRunBeforeCommit() async throws {
        let observation = SidebarScheduledRunQuiescenceObservation()
        let fixture = try SidebarTestFixture(
            stopAndWaitForScheduledTaskRun: { runID in
                observation.record(runID: runID)
            }
        )
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "scheduled-project-mode-archive"
        )
        let threadID = thread.persistentModelID
        let runID = run.persistentModelID
        try configureProjectLikeScheduledThread(
            thread,
            fixture: fixture,
            modeRawValue: AgentThreadMode.project.rawValue
        )
        XCTAssertEqual(try fixture.viewModel.makeThreadArchiveSnapshot(thread).mode, .project)
        observation.inspectUncommittedState = {
            fixture.context.resolveThread(id: threadID)?.archivedAt == nil
        }

        try await fixture.viewModel.archiveThread(thread)

        XCTAssertEqual(observation.runID, runID)
        XCTAssertEqual(observation.actionWasUncommitted, true)
        XCTAssertNotNil(fixture.context.resolveThread(id: threadID)?.archivedAt)
    }

    func testDeleteUnknownModeThreadQuiescesLinkedScheduledRunBeforeCommit() async throws {
        let observation = SidebarScheduledRunQuiescenceObservation()
        let fixture = try SidebarTestFixture(
            stopAndWaitForScheduledTaskRun: { runID in
                observation.record(runID: runID)
            }
        )
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .success,
            conversationID: "scheduled-unknown-mode-delete"
        )
        let workspace = try fixture.taskWorkspaceOwnershipService.createPrivateWorkspace()
        defer { try? fixture.taskWorkspaceOwnershipService.removeOwnedWorkspace(workspace) }
        thread.taskWorkspaceDescriptor = workspace
        run.workspaceKindRawValueSnapshot = ScheduledTaskWorkspaceKind.privateWorkspace.rawValue
        let threadID = thread.persistentModelID
        let runID = run.persistentModelID
        try configureProjectLikeScheduledThread(
            thread,
            fixture: fixture,
            modeRawValue: "future-mode"
        )
        observation.inspectUncommittedState = {
            fixture.context.resolveThread(id: threadID) != nil
        }

        try await fixture.viewModel.deleteThread(thread)

        XCTAssertEqual(observation.runID, runID)
        XCTAssertEqual(observation.actionWasUncommitted, true)
        XCTAssertNil(fixture.context.resolveThread(id: threadID))
        XCTAssertNil(fixture.context.resolveScheduledTaskRun(id: runID)?.thread)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.primaryRoot))
    }

    func testArchiveRejectsUnknownScheduledRunStatusAfterStopAttempt() async throws {
        var stoppedRunID: PersistentIdentifier?
        let fixture = try SidebarTestFixture(
            stopAndWaitForScheduledTaskRun: { runID in
                stoppedRunID = runID
            }
        )
        let (thread, run) = try insertScheduledTaskThread(
            fixture: fixture,
            status: .failure,
            conversationID: "scheduled-unknown-status-archive"
        )
        let threadID = thread.persistentModelID
        let runID = run.persistentModelID
        run.statusRawValue = "future-status"
        try fixture.context.save()

        do {
            try await fixture.viewModel.archiveThread(thread)
            XCTFail("Expected unknown run status to remain non-quiescent")
        } catch {
            guard let sidebarError = error as? SidebarViewModelError,
                  case .scheduledTaskRunStillActive = sidebarError else {
                return XCTFail("Expected scheduledTaskRunStillActive, got \(error)")
            }
        }

        XCTAssertEqual(stoppedRunID, runID)
        XCTAssertNil(fixture.context.resolveThread(id: threadID)?.archivedAt)
        XCTAssertNotNil(
            fixture.context.resolveConversation(conversationID: "scheduled-unknown-status-archive")
        )
    }
}

@MainActor
func insertScheduledTaskThread(
    fixture: SidebarTestFixture,
    status: ScheduledTaskRunStatus,
    conversationID: String
) throws -> (AgentThread, ScheduledTaskRun) {
    let workspaceRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("alveary-scheduled-quiescence-\(UUID().uuidString)", isDirectory: true)
    let run = ScheduledTaskRun(
        occurrenceID: UUID().uuidString,
        definitionID: "definition-\(UUID().uuidString)",
        definitionRevision: 1,
        occurrenceAt: Date(timeIntervalSince1970: 1_800_000_000),
        triggerKind: .scheduled,
        status: status,
        titleSnapshot: "Scheduled task",
        promptSnapshot: "Run scheduled work.",
        timeZoneIdentifierSnapshot: "America/Chicago",
        providerIDSnapshot: "codex",
        effortSnapshot: "high",
        permissionModeSnapshot: "default",
        workspaceKindSnapshot: .project,
        workspaceStrategySnapshot: .localCheckout
    )
    let thread = AgentThread(
        name: "Scheduled task",
        mode: .task,
        taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
            primaryRoot: workspaceRoot.path,
            ownershipStrategy: .projectLocal
        ),
        scheduledTaskRun: run
    )
    thread.conversations = [
        Conversation(id: conversationID, provider: "codex", thread: thread)
    ]
    run.thread = thread
    fixture.context.insert(run)
    fixture.context.insert(thread)
    try fixture.context.save()
    return (thread, run)
}

@MainActor
private final class SidebarScheduledRunQuiescenceObservation {
    var inspectUncommittedState: (() -> Bool)?
    private(set) var runID: PersistentIdentifier?
    private(set) var actionWasUncommitted: Bool?

    func record(runID: PersistentIdentifier) {
        self.runID = runID
        actionWasUncommitted = inspectUncommittedState?()
    }
}

@MainActor
private func configureProjectLikeScheduledThread(
    _ thread: AgentThread,
    fixture: SidebarTestFixture,
    modeRawValue: String
) throws {
    let project = Project(
        path: "/tmp/alveary-scheduled-quiescence-project-\(UUID().uuidString)",
        name: "Scheduled source"
    )
    fixture.context.insert(project)
    thread.modeRawValue = modeRawValue
    thread.project = project
    try fixture.context.save()
}
