import XCTest

@testable import Alveary

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func testFinalizationTimeoutCommitsPartialAndIgnoresLateFinal() async throws {
        let fixture = try makeFixture(text: "Hello")
        fixture.service.setSuspendsStop(true)
        await startRecording(fixture)
        fixture.service.emitPartial("partial")
        await waitUntil { fixture.currentMarkdown == "Hello partial" }

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.service.hasPendingStop }
        await waitUntil { fixture.clock.pendingSleeperCount > 0 }
        XCTAssertTrue(fixture.lifecycleController.isComposerInteractionLocked)

        fixture.clock.advance(by: ChatVoiceInputCoordinator.finalizationTimeout)
        await waitUntil { fixture.coordinator.phase == .cleanup }

        XCTAssertEqual(fixture.currentMarkdown, "Hello partial")
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertFalse(fixture.coordinator.isButtonEnabled)
        XCTAssertFalse(fixture.lifecycleController.isComposerInteractionLocked)
        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            "Dictation was committed. Voice cleanup is still finishing."
        )

        fixture.service.resumePendingStop(with: VoiceInputRecognitionResult(
            transcript: "late final",
            termination: .committed,
            error: nil
        ))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.currentMarkdown, "Hello partial")
        XCTAssertEqual(fixture.flushCount, 1)
    }

    func testFinalizationTimeoutWithoutSpeechRestoresOriginalDraft() async throws {
        let fixture = try makeFixture(text: "Original")
        fixture.service.setSuspendsStop(true)
        await startRecording(fixture)

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.service.hasPendingStop }
        await waitUntil { fixture.clock.pendingSleeperCount > 0 }
        fixture.clock.advance(by: ChatVoiceInputCoordinator.finalizationTimeout)
        await waitUntil { fixture.coordinator.phase == .cleanup }

        XCTAssertEqual(fixture.currentMarkdown, "Original")
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            "No speech was detected. The original draft was restored. Voice cleanup is still finishing."
        )

        fixture.service.resumePendingStop(with: .cancelled)
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testFinalizationTimeoutPreservesRecordingLimitReason() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsStop(true)
        await startRecording(fixture, source: .keyboard)
        await waitUntil { fixture.clock.pendingSleeperCount > 0 }

        fixture.clock.advance(by: ChatVoiceInputCoordinator.recordingLimit)
        await waitUntil { fixture.service.hasPendingStop }
        await waitUntil { fixture.clock.pendingSleeperCount > 0 }
        fixture.clock.advance(by: ChatVoiceInputCoordinator.finalizationTimeout)
        await waitUntil { fixture.coordinator.phase == .cleanup }

        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            "Dictation stopped after the 10-minute limit. Voice cleanup is still finishing."
        )
        XCTAssertEqual(fixture.coordinator.notice?.severity, .warning)

        fixture.service.resumePendingStop(with: .cancelled)
        await waitUntil { fixture.coordinator.phase == .ready }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }

    func testRecordingLimitReasonSurvivesImmediateFinalizationError() async throws {
        let fixture = try makeFixture()
        fixture.service.setStopResult(VoiceInputRecognitionResult(
            transcript: nil,
            termination: .inferenceFailure,
            error: .inference("finalization failed")
        ))
        await startRecording(fixture, source: .mouse)
        await waitUntil { fixture.clock.pendingSleeperCount > 0 }

        fixture.clock.advance(by: ChatVoiceInputCoordinator.recordingLimit)
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            "Dictation stopped after the 10-minute limit. Voice recognition failed: finalization failed"
        )
        XCTAssertEqual(fixture.coordinator.notice?.severity, .error)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
    }

    func testForcedLifecycleStopDoesNotReplaceRecordingLimitNoticeDuringFinalization() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsStop(true)
        await startRecording(fixture, source: .keyboard)
        await waitUntil { fixture.clock.pendingSleeperCount > 0 }

        fixture.clock.advance(by: ChatVoiceInputCoordinator.recordingLimit)
        await waitUntil { fixture.service.hasPendingStop }
        fixture.coordinator.forceStopAndCommit(reason: "Dictation stopped because the app became inactive.")

        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            "Dictation stopped after the 10-minute limit."
        )
        XCTAssertEqual(fixture.coordinator.notice?.severity, .warning)

        fixture.service.resumePendingStop(with: .cancelled)
        await waitUntil { fixture.coordinator.phase == .ready }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }
}
