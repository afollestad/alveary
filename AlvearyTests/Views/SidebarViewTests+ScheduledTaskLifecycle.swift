import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewTests {
    func testScheduledTaskIndicatorUsesAudibleAccessibilityLabel() {
        XCTAssertEqual(SidebarThreadRow.scheduledIndicatorAccessibilityLabel, "Scheduled task")
    }

    func testScheduledTaskRemovalSanitizesReselectedTargetAtPersistenceCommit() async throws {
        for action in SidebarScheduledLifecycleAction.allCases {
            let runGate = SidebarScheduledLifecycleActionGate()
            let cleanupGate = SidebarPostCommitCleanupGate()
            let fixture = try SidebarTestFixture(
                stopAndWaitForScheduledTaskRun: { runID in
                    try await runGate.stopAndWait(runID: runID)
                }
            )
            await fixture.agentsManager.setDestroyObserver { _ in
                await cleanupGate.waitForRelease()
            }
            let (task, run) = try insertScheduledTaskThread(
                fixture: fixture,
                status: .running,
                conversationID: "commit-boundary-\(action.rawValue)"
            )
            let taskID = task.persistentModelID
            runGate.onRelease = {
                run.status = .interrupted
                run.finishedAt = Date()
                try fixture.context.save()
            }
            let appState = AppState()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(taskID)
            let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

            let operation = Task { @MainActor in
                await action.perform(view: view, thread: task)
            }
            await runGate.waitUntilEntered()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(taskID)
            runGate.release()
            await cleanupGate.waitUntilEntered()

            XCTAssertNil(appState.selectedSidebarItem, action.rawValue)
            XCTAssertNil(appState.previousSelection, action.rawValue)
            assertPendingTaskCommand(appState, action: action)
            switch action {
            case .archive:
                XCTAssertNotNil(fixture.context.resolveThread(id: taskID)?.archivedAt)
            case .delete:
                XCTAssertNil(fixture.context.resolveThread(id: taskID))
            }

            cleanupGate.release()
            await operation.value
        }
    }

    func testScheduledTaskRemovalCompletionSanitizesReselectedTarget() async throws {
        for action in SidebarScheduledLifecycleAction.allCases {
            let gate = SidebarScheduledLifecycleActionGate()
            let fixture = try SidebarTestFixture(
                stopAndWaitForScheduledTaskRun: { runID in
                    try await gate.stopAndWait(runID: runID)
                }
            )
            let (task, run) = try insertScheduledTaskThread(
                fixture: fixture,
                status: .running,
                conversationID: "reselected-\(action.rawValue)"
            )
            let taskID = task.persistentModelID
            gate.onRelease = {
                run.status = .interrupted
                run.finishedAt = Date()
                try fixture.context.save()
            }
            let appState = AppState()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(taskID)
            let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

            let operation = Task { @MainActor in
                await action.perform(view: view, thread: task)
            }
            await gate.waitUntilEntered()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(taskID)
            gate.release()
            await operation.value

            XCTAssertNil(appState.selectedSidebarItem, action.rawValue)
            XCTAssertNil(appState.previousSelection, action.rawValue)
            assertPendingTaskCommand(appState, action: action)
            switch action {
            case .archive:
                XCTAssertNotNil(fixture.context.resolveThread(id: taskID)?.archivedAt)
            case .delete:
                XCTAssertNil(fixture.context.resolveThread(id: taskID))
            }
        }
    }

    func testScheduledTaskRemovalCompletionPreservesUnrelatedNavigation() async throws {
        for action in SidebarScheduledLifecycleAction.allCases {
            let gate = SidebarScheduledLifecycleActionGate()
            let fixture = try SidebarTestFixture(
                stopAndWaitForScheduledTaskRun: { runID in
                    try await gate.stopAndWait(runID: runID)
                }
            )
            let (task, run) = try insertScheduledTaskThread(
                fixture: fixture,
                status: .running,
                conversationID: "completion-navigation-\(action.rawValue)"
            )
            gate.onRelease = {
                run.status = .interrupted
                run.finishedAt = Date()
                try fixture.context.save()
            }
            let appState = AppState()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(task.persistentModelID)
            let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

            let operation = Task { @MainActor in
                await action.perform(view: view, thread: task)
            }
            await gate.waitUntilEntered()
            appState.selectedSidebarItem = .scheduled
            gate.release()
            await operation.value

            XCTAssertEqual(appState.selectedSidebarItem, .scheduled, action.rawValue)
            XCTAssertNil(appState.previousSelection, action.rawValue)
            XCTAssertNil(appState.pendingCommand, action.rawValue)
        }
    }

    func testScheduledTaskRemovalFailurePreservesUnrelatedNavigation() async throws {
        for action in SidebarScheduledLifecycleAction.allCases {
            let gate = SidebarScheduledLifecycleActionGate()
            let fixture = try SidebarTestFixture(
                stopAndWaitForScheduledTaskRun: { runID in
                    try await gate.stopAndWait(runID: runID)
                }
            )
            let (task, _) = try insertScheduledTaskThread(
                fixture: fixture,
                status: .running,
                conversationID: "failure-navigation-\(action.rawValue)"
            )
            let taskID = task.persistentModelID
            gate.onRelease = { throw SidebarScheduledLifecycleActionTestError.stopFailed }
            let appState = AppState()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(taskID)
            let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

            let operation = Task { @MainActor in
                await action.perform(view: view, thread: task)
            }
            await gate.waitUntilEntered()
            appState.selectedSidebarItem = .skills
            gate.release()
            await operation.value

            XCTAssertEqual(appState.selectedSidebarItem, .skills, action.rawValue)
            XCTAssertNil(appState.previousSelection, action.rawValue)
            XCTAssertNil(appState.pendingCommand, action.rawValue)
            XCTAssertNil(fixture.context.resolveThread(id: taskID)?.archivedAt, action.rawValue)
            XCTAssertNotNil(fixture.viewModel.sidebarError, action.rawValue)
        }
    }

    func testScheduledTaskRemovalFailureRestoresUnchangedTargetRouting() async throws {
        for action in SidebarScheduledLifecycleAction.allCases {
            let gate = SidebarScheduledLifecycleActionGate()
            let fixture = try SidebarTestFixture(
                stopAndWaitForScheduledTaskRun: { runID in
                    try await gate.stopAndWait(runID: runID)
                }
            )
            let (task, _) = try insertScheduledTaskThread(
                fixture: fixture,
                status: .running,
                conversationID: "failure-restore-\(action.rawValue)"
            )
            gate.onRelease = { throw SidebarScheduledLifecycleActionTestError.stopFailed }
            let appState = AppState()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(task.persistentModelID)
            let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

            let operation = Task { @MainActor in
                await action.perform(view: view, thread: task)
            }
            await gate.waitUntilEntered()
            gate.release()
            await operation.value

            XCTAssertEqual(appState.selectedSidebarItem, .thread(task), action.rawValue)
            XCTAssertEqual(appState.previousSelection, .threadId(task.persistentModelID), action.rawValue)
            XCTAssertNil(appState.pendingCommand, action.rawValue)
        }
    }

    func testScheduledTaskRemovalFailurePreservesNewTaskCommandStartedWhileWaiting() async throws {
        for action in SidebarScheduledLifecycleAction.allCases {
            let gate = SidebarScheduledLifecycleActionGate()
            let fixture = try SidebarTestFixture(
                stopAndWaitForScheduledTaskRun: { runID in
                    try await gate.stopAndWait(runID: runID)
                }
            )
            let (task, _) = try insertScheduledTaskThread(
                fixture: fixture,
                status: .running,
                conversationID: "failure-new-task-\(action.rawValue)"
            )
            gate.onRelease = { throw SidebarScheduledLifecycleActionTestError.stopFailed }
            let appState = AppState()
            appState.selectedSidebarItem = .thread(task)
            appState.previousSelection = .threadId(task.persistentModelID)
            let view = SidebarView(viewModel: fixture.viewModel, appState: appState)

            let operation = Task { @MainActor in
                await action.perform(view: view, thread: task)
            }
            await gate.waitUntilEntered()
            appState.startNewThreadFlow(mode: .task)
            let commandID = appState.pendingCommand?.id
            gate.release()
            await operation.value

            XCTAssertNil(appState.selectedSidebarItem, action.rawValue)
            XCTAssertNil(appState.previousSelection, action.rawValue)
            XCTAssertEqual(appState.pendingCommand?.id, commandID, action.rawValue)
            guard case .newThread(_, let mode) = appState.pendingCommand else {
                return XCTFail("Expected Task command after \(action.rawValue)")
            }
            XCTAssertEqual(mode, .task, action.rawValue)
        }
    }
}

@MainActor
private enum SidebarScheduledLifecycleAction: String, CaseIterable {
    case archive
    case delete

    func perform(view: SidebarView, thread: AgentThread) async {
        switch self {
        case .archive:
            await view.archive(thread)
        case .delete:
            await view.confirmDeleteThread(thread)
        }
    }
}

@MainActor
private final class SidebarScheduledLifecycleActionGate {
    var onRelease: (() throws -> Void)?
    private var didEnter = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func stopAndWait(runID _: PersistentIdentifier) async throws {
        didEnter = true
        let continuations = enteredContinuations
        enteredContinuations.removeAll()
        continuations.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
        try onRelease?()
    }

    func waitUntilEntered() async {
        guard !didEnter else {
            return
        }
        await withCheckedContinuation { continuation in
            enteredContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

@MainActor
private final class SidebarPostCommitCleanupGate {
    private var didEnter = false
    private var enteredContinuations: [CheckedContinuation<Void, Never>] = []
    private var releaseContinuation: CheckedContinuation<Void, Never>?

    func waitForRelease() async {
        didEnter = true
        let continuations = enteredContinuations
        enteredContinuations.removeAll()
        continuations.forEach { $0.resume() }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitUntilEntered() async {
        guard !didEnter else {
            return
        }
        await withCheckedContinuation { continuation in
            enteredContinuations.append(continuation)
        }
    }

    func release() {
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}

private enum SidebarScheduledLifecycleActionTestError: Error {
    case stopFailed
}

@MainActor
private func assertPendingTaskCommand(
    _ appState: AppState,
    action: SidebarScheduledLifecycleAction,
    file: StaticString = #filePath,
    line: UInt = #line
) {
    guard case .newThread(_, let mode) = appState.pendingCommand else {
        return XCTFail("Expected Task command after \(action.rawValue)", file: file, line: line)
    }
    XCTAssertEqual(mode, .task, action.rawValue, file: file, line: line)
}
