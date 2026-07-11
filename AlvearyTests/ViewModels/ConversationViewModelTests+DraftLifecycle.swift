import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testDraftSetupFailureStaysMaterializedWithRetryableAttempt() async throws {
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            useWorktree: true,
            hasCompletedInitialSetup: false
        )
        await fixture.worktreeManager.enqueueCreateResult(.failure(.createFailed))
        let recorder = DraftLifecycleMaterializationRecorder(threadID: fixture.thread.persistentModelID)
        let observer = recorder.start()
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            try await fixture.viewModel.setupAndStart("Build despite setup failure")
            XCTFail("Expected initial setup to fail")
        } catch let error as MockWorktreeManager.MockError {
            XCTAssertEqual(error, .createFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertEqual(failedMessage.content, "Build despite setup failure")
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(fixture.settingsService.current.lastOpenThreadID, fixture.thread.persistentModelID)
        XCTAssertEqual(fixture.settingsService.current.lastOpenConversationID, fixture.conversation.persistentModelID)
    }

    func testDraftSetupCancellationStaysMaterializedAfterAttemptRemoval() async throws {
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            useWorktree: true,
            hasCompletedInitialSetup: false,
            pausesWorktreeCreate: true
        )
        let recorder = DraftLifecycleMaterializationRecorder(threadID: fixture.thread.persistentModelID)
        let observer = recorder.start()
        defer { NotificationCenter.default.removeObserver(observer) }

        let message = "Cancel after materialization"
        let sendTask = Task { try await fixture.viewModel.queueOrSend(message) }
        for _ in 0..<50 where fixture.viewModel.setupPhase == nil {
            try await Task.sleep(for: .milliseconds(5))
        }

        XCTAssertEqual(fixture.viewModel.setupPhase, .creatingWorktree)
        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertEqual(recorder.count, 1)

        await fixture.viewModel.cancel()
        do {
            try await sendTask.value
            XCTFail("Expected CancellationError")
        } catch is CancellationError {
            // expected
        }

        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, message)
        XCTAssertEqual(recorder.count, 1)
        XCTAssertEqual(fixture.settingsService.current.lastOpenThreadID, fixture.thread.persistentModelID)
        XCTAssertEqual(fixture.settingsService.current.lastOpenConversationID, fixture.conversation.persistentModelID)
    }

    func testHiddenDraftMaterializationSaveFailureKeepsDraftAndStartsNoRuntime() async throws {
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            hasCompletedInitialSetup: false,
            draftMaterializationSaver: { throw DraftLifecycleTestError.saveFailed }
        )
        let projectPath = fixture.project.path
        fixture.project.name = "Persist this pending project edit"
        let recorder = DraftLifecycleMaterializationRecorder(threadID: fixture.thread.persistentModelID)
        let observer = recorder.start()
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            try await fixture.viewModel.setupHiddenInitialRuntimeIfNeeded()
            XCTFail("Expected hidden materialization to fail")
        } catch DraftLifecycleTestError.saveFailed {
            // expected
        }

        XCTAssertTrue(try fixture.dbThread().isDraft)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertEqual(recorder.count, 0)
        XCTAssertNil(fixture.settingsService.current.lastOpenThreadID)
        XCTAssertNil(fixture.settingsService.current.lastOpenConversationID)
        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertFalse(fixture.context.hasChanges)

        let verificationContext = ModelContext(fixture.container)
        let descriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == projectPath
        })
        XCTAssertEqual(try verificationContext.fetch(descriptor).first?.name, "Persist this pending project edit")
    }
}

private enum DraftLifecycleTestError: Error {
    case saveFailed
}

private final class DraftLifecycleMaterializationRecorder: @unchecked Sendable {
    private let threadID: PersistentIdentifier
    private let lock = NSLock()
    private var recordedCount = 0

    init(threadID: PersistentIdentifier) {
        self.threadID = threadID
    }

    var count: Int {
        lock.withLock { recordedCount }
    }

    func start() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .threadDraftMaterialized,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let self,
                  notification.userInfo?[ThreadDraftNotificationKey.threadID] as? PersistentIdentifier == threadID else {
                return
            }
            lock.withLock { recordedCount += 1 }
        }
    }
}
