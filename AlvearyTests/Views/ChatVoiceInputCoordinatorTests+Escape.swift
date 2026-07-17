import XCTest

@testable import Alveary

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func testEscapeCancelsAndRestoresExactDraftAndSelection() async throws {
        let fixture = try makeFixture(text: "Original draft")
        let originalSelection = fixture.editor.selection
        await startRecording(fixture)

        fixture.service.emitPartial("replacement")
        await waitUntil { fixture.currentMarkdown == "Original draft replacement" }

        XCTAssertTrue(fixture.coordinator.cancelFromEscape())

        XCTAssertEqual(fixture.currentMarkdown, "Original draft")
        XCTAssertEqual(fixture.editor.selection, originalSelection)
        XCTAssertNil(fixture.editor.undoTextEditInActiveBlock())
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertEqual(fixture.coordinator.notice?.message, "Dictation cancelled.")
        XCTAssertEqual(fixture.service.cancelCaptureCallCount, 1)
        await waitUntil { fixture.service.cancelRecognitionCallCount == 1 }
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testEscapeDuringFinalizationRestoresOriginalAndIgnoresLateFinal() async throws {
        let fixture = try makeFixture(text: "Original draft")
        fixture.service.setSuspendsStop(true)
        fixture.service.setSuspendsCancel(true)
        await startRecording(fixture)
        fixture.service.emitPartial("replacement")
        await waitUntil { fixture.currentMarkdown == "Original draft replacement" }

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.service.hasPendingStop }
        XCTAssertEqual(fixture.coordinator.phase, .finalizing)

        XCTAssertTrue(fixture.coordinator.cancelFromEscape())
        XCTAssertEqual(fixture.currentMarkdown, "Original draft")
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertEqual(fixture.service.cancelCaptureCallCount, 1)
        await waitUntil { fixture.service.cancelRecognitionCallCount == 1 }
        await waitUntil { fixture.service.hasPendingCancel }
        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertFalse(fixture.coordinator.isDraftInteractionLocked)
        XCTAssertFalse(fixture.lifecycleController.isComposerInteractionLocked)

        fixture.service.resumePendingCancel()
        await waitUntil { fixture.coordinator.phase == .ready }

        fixture.service.resumePendingStop(with: VoiceInputRecognitionResult(
            transcript: "late final",
            termination: .committed,
            error: nil
        ))
        await Task.yield()

        XCTAssertEqual(fixture.currentMarkdown, "Original draft")
        XCTAssertEqual(fixture.flushCount, 1)
    }

    func testEscapeClearsBothHeldReleaseMarkersAfterLatchedStop() async throws {
        let fixture = try makeFixture()
        await startRecording(fixture, source: .mouse)

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertTrue(fixture.coordinator.isLatched)

        fixture.service.setSuspendsStop(true)
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingStop }
        XCTAssertEqual(fixture.coordinator.suppressedTrailingRelease, .keyboard)

        XCTAssertTrue(fixture.coordinator.cancelFromEscape())
        await waitUntil { fixture.coordinator.phase == .ready }
        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.keyboard))
        XCTAssertEqual(fixture.coordinator.suppressedTrailingRelease, .keyboard)

        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
        XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
        XCTAssertNil(fixture.coordinator.suppressedTrailingRelease)

        fixture.service.resumePendingStop(with: VoiceInputRecognitionResult(
            transcript: nil,
            termination: .cancelled,
            error: nil
        ))
        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }
}
