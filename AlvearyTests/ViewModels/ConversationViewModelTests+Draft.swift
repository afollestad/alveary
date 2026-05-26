import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
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
