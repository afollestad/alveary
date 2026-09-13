import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func testEditorInteractionUIDuringSuspendedStartupCancelsCaptureBeforeSessionReturns() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)
        fixture.controller.bridgeController?.focusEditorAtDocumentEnd()

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        defer { fixture.service.resumePendingBegin() }
        await waitUntil { fixture.service.hasPendingBegin }
        let startupGeneration = fixture.coordinator.sessionGeneration
        let startupSession = try XCTUnwrap(fixture.service.lock.withLock { fixture.service.state.pendingBeginSession })
        XCTAssertTrue(fixture.editor.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)
        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.mouse))

        // Execute the stale handler after real editor-driven invalidation. Queue ordering
        // remains covered by the callback-delivery tests.
        fixture.coordinator.receiveRecognitionUpdate(
            .partial(session: startupSession, text: "stale partial"),
            generation: startupGeneration
        )
        XCTAssertNil(fixture.coordinator.latestNonemptyTranscript)
        XCTAssertTrue(fixture.coordinator.pendingStartupRecognitionUpdates.isEmpty)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.cancelRecognitionCallCount, 1)
        XCTAssertEqual(fixture.currentMarkdown, "Draft")
        XCTAssertNil(fixture.coordinator.provisionalSession)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
    }

    func testSelectionChangeDuringSuspendedStartupCancelsBeforeNewCaretCanBeUsed() async throws {
        let fixture = try makeFixture(text: "Original")
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)
        let blockID = try XCTUnwrap(fixture.controller.bridgeController?.documentStore.document.blocks.first?.id)
        fixture.editor.focus(blockID: blockID, utf16Offset: 8)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingBegin }
        fixture.editor.focus(blockID: blockID, utf16Offset: 1)

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.cancelRecognitionCallCount, 1)
        XCTAssertEqual(fixture.currentMarkdown, "Original")
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }

    func testDraftChangeDuringSuspendedStartupSynchronouslyCancelsAttempt() async throws {
        let fixture = try makeFixture(text: "Original")
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingBegin }
        reconfigureVoiceEditor(fixture, text: "Replacement", inputDraftRevision: 1)

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.cancelRecognitionCallCount, 1)
        XCTAssertEqual(fixture.currentMarkdown, "Replacement")
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }

    func testComposerContextChangeDuringSuspendedStartupSynchronouslyCancelsAttempt() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }
        fixture.coordinator.updateComposerContext(ChatVoiceInputComposerContext(
            draftIdentity: "voice-test-draft",
            inputDraftRevision: 0,
            attachmentIDs: ["new-attachment"],
            workingDirectory: "/tmp/alveary-voice-tests"
        ))

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.cancelRecognitionCallCount, 1)
        XCTAssertEqual(fixture.currentMarkdown, "Draft")
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
    }
}
