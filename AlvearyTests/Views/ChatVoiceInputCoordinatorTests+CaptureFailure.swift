import BlockInputKit
import XCTest

@testable import Alveary

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func testCoordinatorDeinitDoesNotWaitForAppScopedPreparation() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsPrepare(true)

        fixture.coordinator.accessibilityToggle()
        await waitUntil { fixture.service.hasPendingPrepare }

        weak let weakCoordinator = fixture.coordinator
        fixture.coordinator = nil

        XCTAssertNil(weakCoordinator)
        XCTAssertTrue(fixture.service.hasPendingPrepare)

        fixture.service.resumePendingPrepare()
        await waitUntil { !fixture.service.hasPendingPrepare }
    }

    func testEditorInteractionUIBlocksActivationUntilDismissed() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.controller.bridgeController?.focusEditorAtDocumentEnd()

        XCTAssertTrue(fixture.editor.performCommand(.insertLink(BlockInputInsertLinkCommand(presentation: .modal))))
        XCTAssertTrue(fixture.coordinator.editorHandle.hasPresentedEditorInteractionUI)
        XCTAssertFalse(fixture.coordinator.editorHandle.canStartVoiceInput)
        XCTAssertFalse(fixture.coordinator.physicalPress(.keyboard))
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)

        reconfigureVoiceEditor(
            fixture,
            text: "Draft",
            inputDraftRevision: 0,
            isVoiceInteractionLocked: true
        )
        reconfigureVoiceEditor(fixture, text: "Draft", inputDraftRevision: 0)

        XCTAssertFalse(fixture.coordinator.editorHandle.hasPresentedEditorInteractionUI)
        XCTAssertTrue(fixture.coordinator.editorHandle.canStartVoiceInput)
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testCoordinatorDeinitDoesNotWaitForLateStartupCancellation() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)
        fixture.service.setSuspendsCancel(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }
        fixture.coordinator.forceStopAndCommit()
        fixture.service.resumePendingBegin()
        await waitUntil { fixture.service.hasPendingCancel }

        weak let weakCoordinator = fixture.coordinator
        fixture.coordinator = nil

        XCTAssertNil(weakCoordinator)
        fixture.service.resumePendingCancel()
        await waitUntil { !fixture.service.hasPendingCancel }
    }

    func testAccessibilityStopBlocksRestartUntilHeldPhysicalSourceReleases() async throws {
        for source in [ChatVoiceInputActivationSource.mouse, .keyboard] {
            let fixture = try makeFixture()
            await startRecording(fixture, source: source)

            fixture.coordinator.accessibilityToggle()
            await waitUntil { fixture.coordinator.phase == .ready }

            XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(source))
            let otherSource: ChatVoiceInputActivationSource = source == .mouse ? .keyboard : .mouse
            XCTAssertTrue(fixture.coordinator.physicalPress(otherSource))
            XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
            XCTAssertFalse(fixture.coordinator.physicalRelease(otherSource))

            XCTAssertTrue(fixture.coordinator.physicalRelease(source))
            XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
        }
    }

    func testCaptureFailureWhileSourceIsHeldBlocksActivationUntilRelease() async throws {
        let fixture = try makeFixture()
        await startRecording(fixture, source: .mouse)

        fixture.service.emitCaptureFailure(.deviceConfigurationChanged)
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.mouse))
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.keyboard))

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 2)

        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testUnavailableProvisionalStartupWaitsForCancellationAndHeldRelease() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)
        fixture.service.setSuspendsCancel(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }
        let bridge = try XCTUnwrap(fixture.controller.bridgeController)
        bridge.documentStore.replaceDocument(BlockInputDocument(markdown: "---"))

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.service.hasPendingCancel }

        XCTAssertEqual(fixture.coordinator.phase, .cleanup)
        XCTAssertNil(fixture.coordinator.recognitionSession)
        XCTAssertEqual(fixture.service.shutdownCaptureCallCount, 1)
        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.mouse))
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)

        fixture.service.resumePendingCancel()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertNil(fixture.coordinator.recognitionSession)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
    }

    func testProvisionalInvalidationWhileHeldBlocksOtherSourceUntilRelease() async throws {
        let fixture = try makeFixture(text: "Original")
        await startRecording(fixture, source: .keyboard)
        let bridge = try XCTUnwrap(fixture.controller.bridgeController)
        bridge.documentStore.replaceDocument(BlockInputDocument(markdown: "External change"))

        fixture.service.emitPartial("dictated")
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.keyboard))
        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))

        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
        XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
    }

    func testAccessibilityStartClearsReleaseFromFailedPhysicalStartup() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.repair),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .checkingModel,
            .downloading(kind: .repair, fraction: 1),
            .loadingModel,
            .ready
        ])
        fixture.service.setBeginRecognitionError(
            VoiceInputServiceError.modelLoad("The voice model has not been prepared.")
        )

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil {
            fixture.service.prepareCallCount == 1 && fixture.coordinator.phase == .ready
        }
        XCTAssertEqual(fixture.coordinator.modelModalState, .ready)
        fixture.coordinator.continueAfterModelPreparation()

        fixture.coordinator.accessibilityToggle()
        await waitUntil { fixture.coordinator.phase == .recording }

        XCTAssertNil(fixture.coordinator.startupRelease)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 2)
        fixture.coordinator.accessibilityToggle()
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testForcedStopWhileSourceIsHeldBlocksActivationUntilRelease() async throws {
        let fixture = try makeFixture()
        await startRecording(fixture, source: .keyboard)

        fixture.coordinator.forceStopAndCommit(reason: "Dictation stopped because the composer became unavailable.")
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.keyboard))
        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))

        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
        XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testPartialAndCaptureFailureBeforeRecognitionStartReturnsAreReplayed() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }

        fixture.service.emitPartial("early partial")
        fixture.service.emitCaptureFailure(.deviceConfigurationChanged)
        await waitUntil { fixture.coordinator.pendingStartupRecognitionUpdates.count == 2 }
        XCTAssertEqual(fixture.coordinator.phase, .starting)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 1)
        XCTAssertEqual(fixture.currentMarkdown, "Draft early partial")
        XCTAssertEqual(fixture.coordinator.notice?.severity, .error)
        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.mouse))
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        XCTAssertTrue(fixture.coordinator.releaseBarrier.isEmpty)
    }

    func testPartialBeforeRecognitionStartReturnsCommitsWhenReleaseWasAlreadyForced() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }

        fixture.service.emitPartial("early partial")
        await waitUntil { fixture.coordinator.pendingStartupRecognitionUpdates.count == 1 }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.service.stopRecognitionCallCount, 1)
        XCTAssertEqual(fixture.currentMarkdown, "Draft early partial")
        XCTAssertEqual(fixture.flushCount, 1)
    }

    func testForcedLifecycleStopDoesNotReplaceCaptureFailureNoticeDuringFinalization() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsStop(true)
        await startRecording(fixture, source: .mouse)

        fixture.service.emitCaptureFailure(.deviceConfigurationChanged)
        await waitUntil { fixture.service.hasPendingStop }
        fixture.coordinator.forceStopAndCommit(reason: "Dictation stopped because the window changed.")

        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            VoiceInputServiceError.deviceConfigurationChanged.errorDescription
        )
        XCTAssertEqual(fixture.coordinator.notice?.severity, .error)

        fixture.service.resumePendingStop(with: .cancelled)
        await waitUntil { fixture.coordinator.phase == .ready }
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
    }

    func testRecognitionCallbackDeliveryPreservesPartialAndFailureOrder() async throws {
        let fixture = try makeFixture(text: "Draft")
        await startRecording(fixture, source: .mouse)
        let session = try XCTUnwrap(fixture.coordinator.recognitionSession)
        let generation = fixture.coordinator.sessionGeneration
        let delivery = ChatVoiceInputCallbackDelivery(coordinator: fixture.coordinator)

        delivery.deliverRecognition(.partial(session: session, text: "first"), generation: generation)
        delivery.deliverRecognition(.partial(session: session, text: "second"), generation: generation)
        delivery.deliverRecognition(
            .captureFailed(session: session, error: .deviceConfigurationChanged),
            generation: generation
        )

        await waitUntil { fixture.coordinator.phase == .ready }
        XCTAssertEqual(fixture.currentMarkdown, "Draft second")
        XCTAssertEqual(fixture.coordinator.latestNonemptyTranscript, nil)
        XCTAssertEqual(fixture.coordinator.notice?.severity, .error)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
    }

    func testExternalDraftMutationDuringFinalizationIsNotOverwritten() async throws {
        let fixture = try makeFixture(text: "Original")
        fixture.service.setSuspendsStop(true)
        await startRecording(fixture)
        fixture.service.emitPartial("partial")
        await waitUntil { fixture.currentMarkdown == "Original partial" }

        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { fixture.service.hasPendingStop }
        let bridge = try XCTUnwrap(fixture.controller.bridgeController)
        bridge.documentStore.replaceDocument(BlockInputDocument(markdown: "External change"))

        fixture.service.resumePendingStop(with: VoiceInputRecognitionResult(
            transcript: "final",
            termination: .committed,
            error: nil
        ))
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.currentMarkdown, "External change")
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            "Dictation stopped because the draft changed unexpectedly."
        )
        XCTAssertEqual(fixture.coordinator.notice?.severity, .error)
    }
}
