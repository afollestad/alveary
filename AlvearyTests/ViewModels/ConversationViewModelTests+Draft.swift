import BlockInputKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testFirstDraftSendMaterializesWithDurableUserAttempt() async throws {
        let fixture = try ConversationViewModelTestFixture(isDraft: true, hasCompletedInitialSetup: false)
        let notificationRecorder = DraftMaterializationRecorder(
            expectedThreadID: fixture.thread.persistentModelID
        )
        let observer = notificationRecorder.start()
        defer { NotificationCenter.default.removeObserver(observer) }

        try await fixture.viewModel.setupAndStart("Build the feature")

        let thread = try fixture.dbThread()
        XCTAssertFalse(thread.isDraft)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Build the feature"])
        XCTAssertEqual(fixture.settingsService.current.lastOpenThreadID, thread.persistentModelID)
        XCTAssertEqual(fixture.settingsService.current.lastOpenConversationID, fixture.conversation.persistentModelID)

        let payloads = notificationRecorder.recordedPayloads()
        XCTAssertEqual(payloads.count, 1)
        let payload = try XCTUnwrap(payloads.first)
        XCTAssertEqual(payload[ThreadDraftNotificationKey.threadID] as? PersistentIdentifier, thread.persistentModelID)
        XCTAssertEqual(
            payload[ThreadDraftNotificationKey.conversationID] as? PersistentIdentifier,
            fixture.conversation.persistentModelID
        )
        XCTAssertEqual(payload[ThreadDraftNotificationKey.projectPath] as? String, fixture.project.path)
    }

    func testDraftMaterializationSaveFailureRestoresComposerAndPublishesNothing() async throws {
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            useWorktree: true,
            hasCompletedInitialSetup: false,
            providerId: "codex",
            draftMaterializationSaver: { throw DraftMaterializationTestError.saveFailed }
        )
        let image = draftTestImageAttachment(label: "screen.png")
        let file = draftTestFileAttachment(label: "notes.pdf")
        let appShot = draftTestAppShotAttachment()
        fixture.viewModel.state.inputDraft = "Composer text"
        fixture.viewModel.state.stagedContext = "Context block"
        fixture.viewModel.state.stagedImageAttachments = [image]
        fixture.viewModel.state.stagedFileAttachments = [file]
        fixture.viewModel.state.stagedAppShots = [appShot]
        fixture.viewModel.state.appShotProviderSessionTitleFallback = "Existing fallback"
        let projectPath = fixture.project.path
        fixture.project.name = "Preserved pending project name"
        let notificationRecorder = DraftMaterializationRecorder(
            expectedThreadID: fixture.thread.persistentModelID
        )
        let observer = notificationRecorder.start()
        defer { NotificationCenter.default.removeObserver(observer) }

        do {
            try await fixture.viewModel.setupAndStart("Attempt")
            XCTFail("Expected draft materialization save to fail")
        } catch let error as DraftMaterializationTestError {
            XCTAssertEqual(error, .saveFailed)
        }

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let createCalls = await fixture.worktreeManager.createCalls()
        XCTAssertTrue(try fixture.dbThread().isDraft)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertTrue(fixture.viewModel.state.grouper.items.isEmpty)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Composer text")
        XCTAssertEqual(fixture.viewModel.state.stagedContext, "Context block")
        XCTAssertEqual(fixture.viewModel.state.stagedImageAttachments, [image])
        XCTAssertEqual(fixture.viewModel.state.stagedFileAttachments, [file])
        XCTAssertEqual(fixture.viewModel.state.stagedAppShots, [appShot])
        XCTAssertEqual(fixture.viewModel.state.appShotProviderSessionTitleFallback, "Existing fallback")
        XCTAssertTrue(notificationRecorder.recordedPayloads().isEmpty)
        XCTAssertNil(fixture.settingsService.current.lastOpenThreadID)
        XCTAssertNil(fixture.settingsService.current.lastOpenConversationID)
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertTrue(createCalls.isEmpty)
        let verificationContext = ModelContext(fixture.container)
        let projectDescriptor = FetchDescriptor<Project>(predicate: #Predicate { project in
            project.path == projectPath
        })
        XCTAssertEqual(try verificationContext.fetch(projectDescriptor).first?.name, "Preserved pending project name")
    }

    func testHiddenRuntimeSetupMaterializesDraftBeforeStarting() async throws {
        let fixture = try ConversationViewModelTestFixture(isDraft: true, hasCompletedInitialSetup: false)

        try await fixture.viewModel.setupHiddenInitialRuntimeIfNeeded()

        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertTrue(try fixture.userMessages().isEmpty)
    }

    func testImageOnlyFirstSendMaterializesDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(isDraft: true, hasCompletedInitialSetup: false)
        let attachment = draftTestImageAttachment(label: "screen.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.setupAndStart("")

        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertEqual(userMessage.content, "")
        XCTAssertEqual(userMessage.persistedImageAttachments, [attachment])
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)
    }

    func testFileOnlyFirstSendMaterializesDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(isDraft: true, hasCompletedInitialSetup: false)
        let attachment = draftTestFileAttachment(label: "notes.pdf")
        fixture.viewModel.state.stagedFileAttachments = [attachment]

        try await fixture.viewModel.setupAndStart("")

        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertEqual(userMessage.content, attachment.markdownLink)
        XCTAssertEqual(userMessage.persistedFileAttachments, [attachment])
        XCTAssertTrue(fixture.viewModel.state.stagedFileAttachments.isEmpty)
    }

    func testAppShotOnlyFirstSendMaterializesDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            hasCompletedInitialSetup: false,
            providerId: "codex"
        )
        let appShot = draftTestAppShotAttachment()
        fixture.viewModel.state.stagedAppShots = [appShot]

        try await fixture.viewModel.setupAndStart("")

        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertEqual(userMessage.content, "")
        XCTAssertEqual(userMessage.persistedAppShotAttachments, [PersistedAppShotAttachment(appShot: appShot)])
        XCTAssertTrue(fixture.viewModel.state.stagedAppShots.isEmpty)
    }

    func testGoalModeFirstSendMaterializesDraft() async throws {
        let fixture = try ConversationViewModelTestFixture(
            isDraft: true,
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        fixture.viewModel.setGoalModeArmed(true)

        try await fixture.viewModel.startGoal("Ship goal mode")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertFalse(try fixture.dbThread().isDraft)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Ship goal mode"])
        XCTAssertEqual(spawnCalls.first?.config.initialGoal, "Ship goal mode")
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testBlockInputMutationRecordsCheapDraftStateWithoutPublishingMarkdown() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.replaceInputDraft("Seed")
        fixture.viewModel.state.isAwaitingHandoffSteering = true
        fixture.viewModel.state.handoffSteeringCountdownRemaining = 5
        fixture.viewModel.state.handoffSteeringDraftBaseline = "Seed"
        fixture.viewModel.state.pendingHandoffOutput = "Seed"
        fixture.viewModel.state.handoffCountdownRemaining = 5
        fixture.viewModel.state.handoffDraftBaseline = "Seed"

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Seed")
        XCTAssertEqual(fixture.viewModel.state.inputDraftSource, .blockInputMarkdown)
        XCTAssertEqual(fixture.viewModel.state.inputDraftDirtyRevision, 1)
        XCTAssertFalse(fixture.viewModel.state.inputDraftIsEffectivelyEmpty)
        XCTAssertNil(fixture.viewModel.state.handoffSteeringCountdownRemaining)
        XCTAssertNil(fixture.viewModel.state.handoffCountdownRemaining)
        XCTAssertEqual(fixture.viewModel.state.pendingHandoffOutput, "Seed")
    }

    func testBlockInputDraftPublishCancelsStaleSnapshot() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "First"),
            delay: .milliseconds(30)
        )
        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "Second"),
            delay: .milliseconds(5)
        )

        try await waitUntil("block input draft publish completes", timeout: .seconds(1)) {
            fixture.viewModel.state.inputDraft == "Second" &&
                fixture.viewModel.state.inputDraftPublishTask == nil
        }

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Second")
        XCTAssertEqual(fixture.viewModel.state.inputDraftSource, .blockInputMarkdown)
        XCTAssertFalse(fixture.viewModel.state.inputDraftIsEffectivelyEmpty)
        XCTAssertNil(fixture.viewModel.state.inputDraftPublishTask)
    }

    func testUserDraftPublishesDoNotAdvanceExternalReplacementRevision() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.publishComposerDraft("Legacy edit", source: .legacyText)
        XCTAssertEqual(fixture.viewModel.state.inputDraftRevision, 0)

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "BlockInput edit"),
            delay: .milliseconds(1)
        )

        try await waitUntil("block input draft publish completes", timeout: .seconds(1)) {
            fixture.viewModel.state.inputDraft == "BlockInput edit"
        }

        XCTAssertEqual(fixture.viewModel.state.inputDraftRevision, 0)

        fixture.viewModel.clearInputDraft(source: .blockInputMarkdown)

        XCTAssertEqual(fixture.viewModel.state.inputDraftRevision, 1)
    }

    func testBlockInputMutationCancelsPendingPublishBeforeNextChange() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "Stale"),
            delay: .milliseconds(30)
        )
        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(fixture.viewModel.state.inputDraftPublishTask)
    }

    func testExternalDraftReplacementCancelsPendingBlockInputPublish() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "Stale"),
            delay: .milliseconds(30)
        )
        fixture.viewModel.clearInputDraft(source: .blockInputMarkdown)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertEqual(fixture.viewModel.state.inputDraftSource, .blockInputMarkdown)
        XCTAssertTrue(fixture.viewModel.state.inputDraftIsEffectivelyEmpty)
    }

    func testExternalDraftReplacementIgnoresLateBlockInputDocumentChange() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        fixture.viewModel.clearInputDraft(source: .blockInputMarkdown)
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "Late stale edit"),
            delay: .milliseconds(1)
        )

        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertNil(fixture.viewModel.state.inputDraftPublishTask)
    }

    func testFlushDraftFromEditorIgnoresLateBlockInputDocumentChange() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.composerDraftSnapshotProvider = {
            ComposerDraft(
                text: "Flushed edit",
                source: .blockInputMarkdown,
                isEffectivelyEmpty: false
            )
        }

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        let draft = fixture.viewModel.flushDraftFromEditor()
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "Late stale edit"),
            delay: .milliseconds(1)
        )

        try await Task.sleep(for: .milliseconds(40))

        XCTAssertEqual(draft.text, "Flushed edit")
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Flushed edit")
        XCTAssertNil(fixture.viewModel.state.inputDraftPublishTask)
    }

    func testAppendInputDraftPreservesCurrentDraftSource() throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.replaceInputDraft("Existing", source: .blockInputMarkdown)
        fixture.viewModel.appendToInputDraft("Queued edit")

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Existing\n\nQueued edit")
        XCTAssertEqual(fixture.viewModel.state.inputDraftSource, .blockInputMarkdown)
    }

    func testStateReplacementCancelsPendingBlockInputPublish() async throws {
        let fixture = try ConversationViewModelTestFixture()

        fixture.viewModel.recordBlockInputDraftMutation(isEffectivelyEmpty: false)
        fixture.viewModel.scheduleBlockInputDraftPublish(
            BlockInputDocument(markdown: "Stale"),
            delay: .milliseconds(30)
        )
        let replacementState = ConversationState()
        replacementState.inputDraftDirtyRevision = fixture.viewModel.state.inputDraftDirtyRevision
        fixture.viewModel.replaceState(with: replacementState)

        try await Task.sleep(for: .milliseconds(80))

        XCTAssertEqual(fixture.viewModel.state.inputDraft, "")
        XCTAssertTrue(fixture.viewModel.state.inputDraftIsEffectivelyEmpty)
    }
}

private final class DraftMaterializationRecorder: @unchecked Sendable {
    private let expectedThreadID: PersistentIdentifier
    private let lock = NSLock()
    private var payloads: [[AnyHashable: Any]] = []

    init(expectedThreadID: PersistentIdentifier) {
        self.expectedThreadID = expectedThreadID
    }

    func recordIfMatching(_ payload: [AnyHashable: Any]?) {
        guard let payload,
              payload[ThreadDraftNotificationKey.threadID] as? PersistentIdentifier == expectedThreadID else {
            return
        }
        lock.withLock {
            payloads.append(payload)
        }
    }

    func recordedPayloads() -> [[AnyHashable: Any]] {
        lock.withLock { payloads }
    }

    func start() -> NSObjectProtocol {
        NotificationCenter.default.addObserver(
            forName: .threadDraftMaterialized,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            self?.recordIfMatching(notification.userInfo)
        }
    }
}

private enum DraftMaterializationTestError: Error, Equatable {
    case saveFailed
}

private func draftTestImageAttachment(label: String) -> LocalImageAttachment {
    LocalImageAttachment(
        id: UUID().uuidString,
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(label)"),
        label: label,
        createdAt: Date()
    )
}

private func draftTestFileAttachment(label: String) -> LocalFileAttachment {
    LocalFileAttachment(
        id: UUID().uuidString,
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString)-\(label)"),
        label: label,
        createdAt: Date()
    )
}

private func draftTestAppShotAttachment() -> AppShotAttachment {
    let screenshot = draftTestImageAttachment(label: "app-shot.png")
    return AppShotAttachment(
        appName: "Preview",
        bundleIdentifier: "com.apple.Preview",
        windowTitle: "Document",
        screenshot: screenshot,
        axTreeText: "standard window Document",
        focusedElementSummary: "button Open",
        attachmentStoreRoot: screenshot.fileURL.deletingLastPathComponent()
    )
}
