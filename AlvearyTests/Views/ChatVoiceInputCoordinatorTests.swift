import AppKit
import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
final class ChatVoiceInputCoordinatorTests: XCTestCase {
    func testPreparationConsumesInitialPhysicalPress() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.installation),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .checkingPermission,
            .checkingModel,
            .downloading(kind: .installation, fraction: 0.5),
            .loadingModel,
            .ready
        ])

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.prepareCallCount, 1)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertEqual(fixture.coordinator.modelModalState, .ready)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        fixture.coordinator.accessibilityToggle()
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)

        fixture.coordinator.continueAfterModelPreparation()
        XCTAssertNil(fixture.coordinator.modelModalState)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .recording }

        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testPhysicalActivationStopsAccessibilityStartedRecording() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)

        for source in [ChatVoiceInputActivationSource.mouse, .keyboard] {
            fixture.coordinator.accessibilityToggle()
            await waitUntil { fixture.coordinator.phase == .recording }

            XCTAssertTrue(fixture.coordinator.isLatched)
            XCTAssertTrue(fixture.coordinator.physicalPress(source))
            XCTAssertTrue(fixture.coordinator.physicalRelease(source))
            await waitUntil { fixture.coordinator.phase == .ready }
        }

        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 2)
    }

    func testForcedStopWhileRecognitionIsStartingWaitsForOwningCancellation() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)
        fixture.service.setSuspendsCancel(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }
        let startingGeneration = fixture.coordinator.sessionGeneration

        fixture.coordinator.forceStopAndCommit(reason: "Dictation stopped because the window changed.")

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertFalse(fixture.coordinator.isButtonEnabled)
        XCTAssertGreaterThan(fixture.coordinator.sessionGeneration, startingGeneration)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.service.hasPendingCancel }

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertFalse(fixture.coordinator.isButtonEnabled)

        fixture.service.resumePendingCancel()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.cancelRecognitionCallCount, 1)
        XCTAssertNil(fixture.coordinator.recognitionSession)
    }

    func testEditorDetachWhileRecognitionIsStartingCancelsLateSession() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingBegin }

        fixture.controller.detach()

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertFalse(fixture.coordinator.isButtonEnabled)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.service.cancelRecognitionCallCount == 1 }
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertNil(fixture.coordinator.recognitionSession)
    }

    func testCoordinatorDeinitWhileRecognitionIsStartingCancelsLateSession() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }

        weak let weakCoordinator = fixture.coordinator
        fixture.coordinator = nil

        XCTAssertNil(weakCoordinator)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.service.cancelRecognitionCallCount == 1 }
    }

    func testModelLoadRepairConsumesOriginalPressAndRequiresFreshActivation() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.repair),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .checkingModel,
            .downloading(kind: .repair, fraction: 0.5),
            .loadingModel,
            .ready
        ])
        fixture.service.setBeginRecognitionError(
            VoiceInputServiceError.modelLoad("The voice model has not been prepared.")
        )

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil {
            fixture.service.prepareCallCount == 1 && fixture.coordinator.phase == .ready
        }

        XCTAssertTrue(fixture.coordinator.modelIsReady)
        XCTAssertEqual(fixture.service.prepareCallCount, 1)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertEqual(fixture.coordinator.modelModalState, .ready)
        fixture.coordinator.continueAfterModelPreparation()

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 2)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testPersistentModelLoadFailureRepairsOnlyOncePerFreshActivation() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.repair),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .checkingModel,
            .downloading(kind: .repair, fraction: 0.5),
            .loadingModel,
            .ready
        ])
        fixture.service.setPersistentBeginRecognitionError(
            VoiceInputServiceError.modelLoad("The voice model has not been prepared.")
        )

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil {
            fixture.service.prepareCallCount == 1 && fixture.coordinator.phase == .ready
        }

        XCTAssertTrue(fixture.coordinator.modelIsReady)
        XCTAssertEqual(fixture.service.prepareCallCount, 1)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertEqual(fixture.coordinator.modelModalState, .ready)
        fixture.coordinator.continueAfterModelPreparation()

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil {
            fixture.service.prepareCallCount == 2 && fixture.coordinator.phase == .ready
        }
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 2)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertEqual(fixture.coordinator.modelModalState, .ready)
        fixture.coordinator.continueAfterModelPreparation()

        fixture.service.setPersistentBeginRecognitionError(nil)
        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testUndeterminedPermissionPreparationConsumesStartupPress() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .inMemory,
            requestedMicrophonePermission: true
        ))
        fixture.service.setPreparationProgress([
            .checkingPermission,
            .loadingModel,
            .ready
        ])
        fixture.service.setBeginRecognitionError(VoiceInputServiceError.permissionNotDetermined)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil {
            fixture.service.prepareCallCount == 1 && fixture.coordinator.phase == .ready
        }

        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.keyboard))
        XCTAssertEqual(fixture.coordinator.modelModalState, .ready)
        XCTAssertNil(fixture.coordinator.notice)
        fixture.coordinator.continueAfterModelPreparation()

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 2)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testPartialTranscriptCollapsesWhitespaceBeforeInsertion() async throws {
        let fixture = try makeFixture(text: "Hello")
        await startRecording(fixture)

        fixture.service.emitPartial("  dictated\n\nwords\t ")
        await waitUntil { fixture.currentMarkdown == "Hello dictated words" }

        XCTAssertEqual(fixture.coordinator.latestNonemptyTranscript, "dictated words")
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testNilSelectionUsesResolvedEditableCaretForBoundarySpacing() async throws {
        let fixture = try makeFixture(text: "Hello\n\n---")
        XCTAssertNil(fixture.editor.selection)

        await startRecording(fixture)

        guard case .cursor(let cursor) = fixture.editor.selection else {
            return XCTFail("Expected BlockInputKit to resolve a fallback caret.")
        }
        let targetBlock = try XCTUnwrap(fixture.editor.document.blocks.first(where: { $0.id == cursor.blockID }))
        XCTAssertEqual(targetBlock.text, "Hello")
        XCTAssertEqual(cursor.utf16Offset, 5)

        fixture.service.emitPartial("dictated")
        await waitUntil { fixture.currentMarkdown == "Hello dictated\n\n---" }

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testBoundarySpacingMatchesComposerContext() throws {
        let cases = [
            VoiceBoundaryTestCase(text: "Helloworld", location: 5, replacement: " dictated "),
            VoiceBoundaryTestCase(text: "Hello,world", location: 6, replacement: " dictated "),
            VoiceBoundaryTestCase(text: "(text", location: 1, replacement: "dictated "),
            VoiceBoundaryTestCase(text: "text)", location: 4, replacement: " dictated"),
            VoiceBoundaryTestCase(text: "Hello  world", location: 6, replacement: "dictated"),
            VoiceBoundaryTestCase(text: "\"text\"", location: 1, length: 4, replacement: "dictated")
        ]

        for testCase in cases {
            let context = try XCTUnwrap(ComposerVoiceInsertionContext.capture(
                blockText: testCase.text,
                range: testCase.range
            ))
            XCTAssertEqual(
                context.replacementText(for: "dictated"),
                testCase.replacement,
                "Unexpected boundary spacing for \(testCase.text) at \(testCase.range)"
            )
        }
    }

    func testBoundaryCaptureUsesComposedCharactersAndRejectsInvalidUTF16Ranges() throws {
        let context = try XCTUnwrap(ComposerVoiceInsertionContext.capture(
            blockText: "A👩🏽‍💻B",
            range: NSRange(location: ("A👩🏽‍💻" as NSString).length, length: 0)
        ))

        XCTAssertEqual(context.precedingText, "👩🏽‍💻")
        XCTAssertEqual(context.followingText, "B")
        XCTAssertNil(ComposerVoiceInsertionContext.capture(
            blockText: "text",
            range: NSRange(location: 5, length: 0)
        ))
        XCTAssertNil(ComposerVoiceInsertionContext.capture(
            blockText: "text",
            range: NSRange(location: 3, length: 2)
        ))
    }

    func testBlockSelectionMakesVoiceInputUnavailableUntilTextSelectionReturns() throws {
        let fixture = try makeFixture(text: "Hello")
        let blockID = try XCTUnwrap(fixture.editor.document.blocks.first?.id)

        fixture.controller.latestSelection = .blocks([blockID])
        XCTAssertFalse(fixture.coordinator.editorHandle.supportsVoiceInputSelection)

        fixture.controller.latestSelection = .cursor(BlockInputCursor(blockID: blockID, utf16Offset: 5))
        XCTAssertTrue(fixture.coordinator.editorHandle.supportsVoiceInputSelection)
    }

    func testShortReleaseLatchesAndFreshActivationStops() async throws {
        let fixture = try makeFixture()
        await startRecording(fixture, source: .mouse)

        fixture.clock.advance(by: .milliseconds(299))
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))

        XCTAssertEqual(fixture.coordinator.phase, .recording)
        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 0)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 1)
        fixture.coordinator.accessibilityToggle()
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }

    func testReleaseAtHoldThresholdStopsImmediately() async throws {
        let fixture = try makeFixture()
        await startRecording(fixture, source: .mouse)

        fixture.clock.advance(by: .milliseconds(300))
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 1)
    }

    func testOtherSourceIsIgnoredWhilePhysicalSourceIsHeld() async throws {
        let fixture = try makeFixture()
        await startRecording(fixture, source: .mouse)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        XCTAssertFalse(fixture.coordinator.physicalRelease(.keyboard))
        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 0)
        XCTAssertEqual(fixture.coordinator.phase, .recording)

        fixture.clock.advance(by: .milliseconds(100))
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertEqual(fixture.coordinator.phase, .recording)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.coordinator.phase == .ready }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }

    func testForcedReleaseStopsBeforeHoldThreshold() async throws {
        let fixture = try makeFixture()
        await startRecording(fixture, source: .keyboard)

        fixture.clock.advance(by: .milliseconds(1))
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 1)
    }

    func testStopWithNoSpeechRestoresOriginalDraft() async throws {
        let fixture = try makeFixture(text: "Keep this")
        let originalSelection = fixture.editor.selection
        await startRecording(fixture)

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.currentMarkdown, "Keep this")
        XCTAssertEqual(fixture.editor.selection, originalSelection)
        XCTAssertEqual(fixture.flushCount, 1)
    }

    func testFinalNonemptyTranscriptWinsOverLatestPartial() async throws {
        let fixture = try makeFixture(text: "Hello")
        fixture.service.setStopResult(VoiceInputRecognitionResult(
            transcript: "  final\nanswer  ",
            termination: .committed,
            error: nil
        ))
        await startRecording(fixture)

        fixture.service.emitPartial("partial answer")
        await waitUntil { fixture.currentMarkdown == "Hello partial answer" }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.currentMarkdown, "Hello final answer")
        XCTAssertEqual(fixture.flushCount, 1)
    }

    func testCommittedDictationUsesSingleUndoAndRedoStep() async throws {
        let fixture = try makeFixture(text: "Hello")
        await startRecording(fixture)

        fixture.service.emitPartial("first")
        await waitUntil { fixture.currentMarkdown == "Hello first" }
        fixture.service.emitPartial("final partial")
        await waitUntil { fixture.currentMarkdown == "Hello final partial" }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.editor.undoTextEditInActiveBlock()?.actionName, "Text Edit")
        XCTAssertEqual(fixture.currentMarkdown, "Hello")
        XCTAssertNil(fixture.editor.undoTextEditInActiveBlock())

        XCTAssertEqual(fixture.editor.redoTextEditInActiveBlock()?.actionName, "Text Edit")
        XCTAssertEqual(fixture.currentMarkdown, "Hello final partial")
        XCTAssertNil(fixture.editor.redoTextEditInActiveBlock())
    }

    func testRecordingLimitCommitsAndRequiresHeldSourceRelease() async throws {
        let fixture = try makeFixture(text: "Hello")
        await startRecording(fixture, source: .mouse)
        fixture.service.emitPartial("limit result")
        await waitUntil { fixture.currentMarkdown == "Hello limit result" }
        await waitUntil { fixture.clock.pendingSleeperCount > 0 }

        fixture.clock.advance(by: ChatVoiceInputCoordinator.recordingLimit)
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 1)
        XCTAssertEqual(fixture.currentMarkdown, "Hello limit result")
        XCTAssertEqual(fixture.coordinator.notice?.message, "Dictation stopped after the 10-minute limit.")

        fixture.coordinator.accessibilityToggle()
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 2)

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testEditorDetachCommitsSynchronouslyAndWaitsForServiceCleanup() async throws {
        let fixture = try makeFixture(text: "Hello")
        fixture.service.setSuspendsStop(true)
        await startRecording(fixture)
        fixture.service.emitPartial("detached")
        await waitUntil { fixture.currentMarkdown == "Hello detached" }

        fixture.controller.detach()

        XCTAssertEqual(fixture.currentMarkdown, "Hello detached")
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertFalse(fixture.coordinator.isButtonEnabled)
        await waitUntil { fixture.service.hasPendingStop }
        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 1)

        fixture.service.resumePendingStop(with: VoiceInputRecognitionResult(
            transcript: "late replacement",
            termination: .committed,
            error: nil
        ))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.currentMarkdown, "Hello detached")
        XCTAssertEqual(fixture.flushCount, 1)
    }
}
