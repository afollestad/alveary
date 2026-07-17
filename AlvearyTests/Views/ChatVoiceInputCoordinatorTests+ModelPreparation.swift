import XCTest

@testable import Alveary

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func testReadyModalBlocksActivationUntilContinueAndFreshPress() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.installation),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .checkingModel,
            .downloading(kind: .installation, fraction: 1),
            .loadingModel,
            .ready
        ])

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.modelModalState == .ready }

        XCTAssertFalse(fixture.coordinator.isButtonEnabled)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        fixture.coordinator.accessibilityToggle()
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)

        fixture.coordinator.continueAfterModelPreparation()
        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertTrue(fixture.coordinator.isButtonEnabled)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard, forced: true))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testDownloadedProgressDoesNotEnableContinueBeforePreparationReturns() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.installation),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .downloading(kind: .installation, fraction: 0.75),
            .ready
        ])
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitUntil {
            fixture.coordinator.modelModalState == .preparing(
                .downloading(kind: .installation, fraction: 0.75)
            )
        }

        XCTAssertEqual(
            fixture.coordinator.modelModalState,
            .preparing(.downloading(kind: .installation, fraction: 0.75))
        )
        fixture.coordinator.continueAfterModelPreparation()
        XCTAssertEqual(
            fixture.coordinator.modelModalState,
            .preparing(.downloading(kind: .installation, fraction: 0.75))
        )

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.modelModalState == .ready }
    }

    func testCancelKeepsModalUntilSuspendedPreparationReturns() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.installation),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .checkingPermission,
            .downloading(kind: .installation, fraction: 0.25)
        ])
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitUntil {
            fixture.coordinator.modelModalState == .preparing(
                .downloading(kind: .installation, fraction: 0.25)
            )
        }
        XCTAssertEqual(
            fixture.coordinator.modelModalState,
            .preparing(.downloading(kind: .installation, fraction: 0.25))
        )

        fixture.coordinator.cancelModelPreparationFromModal()

        XCTAssertEqual(fixture.coordinator.modelModalState, .cancelling)
        XCTAssertTrue(fixture.service.hasPendingPrepare)
        XCTAssertFalse(fixture.coordinator.isButtonEnabled)

        fixture.coordinator.receivePreparationProgress(
            .loadingModel,
            generation: fixture.coordinator.preparationGeneration
        )
        XCTAssertEqual(fixture.coordinator.modelModalState, .cancelling)

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.modelModalState == nil }

        XCTAssertEqual(fixture.coordinator.phase, .idle)
        XCTAssertFalse(fixture.coordinator.modelIsReady)
        XCTAssertEqual(fixture.announcements.last, "Voice model setup cancelled")
    }

    func testModelPreparationFailureStaysInModalUntilCancel() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationProgress([.checkingModel])
        fixture.service.setPreparationError(VoiceInputServiceError.modelDownload("offline"))

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil {
            guard let state = fixture.coordinator.modelModalState else { return false }
            if case .failed = state { return true }
            return false
        }

        XCTAssertEqual(
            fixture.coordinator.modelModalState,
            .failed(
                message: "The voice model could not be downloaded. Check your connection and try again.",
                recovery: nil
            )
        )
        XCTAssertNil(fixture.coordinator.notice)
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        fixture.coordinator.accessibilityToggle()
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertNotNil(fixture.coordinator.modelModalState)

        fixture.coordinator.cancelModelPreparationFromModal()
        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertEqual(fixture.announcements.last, "Voice model setup cancelled")
    }

    func testPermissionFailuresEncodeOnlyDeniedAsMicrophoneSettingsRecovery() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationProgress([.checkingPermission])
        fixture.service.setPreparationError(VoiceInputServiceError.permissionDenied)

        fixture.coordinator.accessibilityToggle()
        await waitUntil {
            guard let state = fixture.coordinator.modelModalState else { return false }
            if case .failed = state { return true }
            return false
        }

        let expectedState = ChatVoiceInputModelModalState.failed(
            message: "Microphone access is off. Allow Alveary in System Settings to use dictation.",
            recovery: .microphoneSettings
        )
        XCTAssertEqual(fixture.coordinator.modelModalState, expectedState)
        XCTAssertTrue(VoiceInputModelModalPresentation(state: expectedState).showsMicrophoneSettings)

        let restrictedFixture = try makeFixture()
        restrictedFixture.service.setPreparationProgress([.checkingPermission])
        restrictedFixture.service.setPreparationError(VoiceInputServiceError.permissionRestricted)

        restrictedFixture.coordinator.accessibilityToggle()
        await waitUntil {
            guard let state = restrictedFixture.coordinator.modelModalState else { return false }
            if case .failed = state { return true }
            return false
        }

        let restrictedState = ChatVoiceInputModelModalState.failed(
            message: "Microphone access is restricted on this Mac.",
            recovery: nil
        )
        XCTAssertEqual(restrictedFixture.coordinator.modelModalState, restrictedState)
        XCTAssertFalse(VoiceInputModelModalPresentation(state: restrictedState).showsMicrophoneSettings)
    }

    func testLoadedModelPermissionFailuresUseBlockingModalWithoutRepreparing() async throws {
        let cases: [(VoiceInputServiceError, ChatVoiceInputModelModalState)] = [
            (
                .permissionDenied,
                .failed(
                    message: "Microphone access is off. Allow Alveary in System Settings to use dictation.",
                    recovery: .microphoneSettings
                )
            ),
            (
                .permissionRestricted,
                .failed(
                    message: "Microphone access is restricted on this Mac.",
                    recovery: nil
                )
            )
        ]

        for (error, expectedState) in cases {
            let fixture = try makeFixture()
            markModelReady(fixture)
            fixture.service.setBeginRecognitionError(error)

            fixture.coordinator.accessibilityToggle()
            await waitUntil { fixture.coordinator.modelModalState == expectedState }

            XCTAssertEqual(fixture.coordinator.modelModalState, expectedState)
            XCTAssertNil(fixture.coordinator.notice)
            XCTAssertEqual(fixture.coordinator.phase, .ready)
            XCTAssertTrue(fixture.coordinator.modelIsReady)
            XCTAssertEqual(fixture.service.prepareCallCount, 0)
            XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
        }
    }

    func testLaterCoordinatorUsesReadinessAfterFirstModalContinues() async throws {
        let service = FakeChatVoiceInputService()
        service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.installation),
            requestedMicrophonePermission: false
        ))
        service.setPreparationProgress([
            .checkingModel,
            .downloading(kind: .installation, fraction: 1),
            .loadingModel,
            .ready
        ])
        let lifecycleController = VoiceInputLifecycleController(service: service)
        let first = try makeFixture(service: service, lifecycleController: lifecycleController)
        let second = try makeFixture(service: service, lifecycleController: lifecycleController)

        first.coordinator.accessibilityToggle()
        await waitUntil { first.coordinator.phase == .ready }
        first.coordinator.continueAfterModelPreparation()

        second.coordinator.accessibilityToggle()
        await waitUntil { second.coordinator.phase == .recording }

        XCTAssertEqual(service.prepareCallCount, 1)
        XCTAssertEqual(service.beginRecognitionCallCount, 1)
        XCTAssertTrue(second.coordinator.modelIsReady)

        second.coordinator.accessibilityToggle()
        await waitUntil { second.coordinator.phase == .ready }
    }

    func testLaterComposerStaysUnavailableWhilePreviousRecognitionCleansUp() async throws {
        let service = FakeChatVoiceInputService()
        let lifecycleController = VoiceInputLifecycleController(service: service)
        let first = try makeFixture(service: service, lifecycleController: lifecycleController)
        let second = try makeFixture(service: service, lifecycleController: lifecycleController)

        await startRecording(first)
        service.setSuspendsStop(true)
        first.coordinator.forceVoiceInputCommitSynchronously()
        await waitUntil { service.hasPendingStop }

        XCTAssertEqual(first.coordinator.phase, .cleanup)
        XCTAssertTrue(second.coordinator.isVoiceInputOwnedElsewhere)
        XCTAssertFalse(second.coordinator.isButtonEnabled)
        XCTAssertTrue(second.coordinator.physicalPress(.mouse))
        XCTAssertEqual(
            second.coordinator.notice?.message,
            ChatVoiceInputCoordinator.voiceInputOwnedElsewhereMessage
        )
        XCTAssertEqual(service.beginRecognitionCallCount, 1)

        service.resumePendingStop(with: VoiceInputRecognitionResult(
            transcript: nil,
            termination: .committed,
            error: nil
        ))
        await waitUntil { first.coordinator.phase == .ready }
        await waitUntil { !second.coordinator.isVoiceInputOwnedElsewhere }

        XCTAssertTrue(second.coordinator.isButtonEnabled)
    }

    func testLifecyclePublishesInteractionLockWhenCoordinatorPhaseChanges() async throws {
        let fixture = try makeFixture()
        markModelReady(fixture)
        var observedStates: [Bool] = []
        let observer = NotificationCenter.default.addObserver(
            forName: .voiceInputComposerInteractionLockChanged,
            object: fixture.lifecycleController,
            queue: .main
        ) { [weak lifecycleController = fixture.lifecycleController] _ in
            MainActor.assumeIsolated {
                observedStates.append(lifecycleController?.isComposerInteractionLocked == true)
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertEqual(observedStates.last, true)

        fixture.service.setSuspendsStop(true)
        fixture.coordinator.forceVoiceInputCommitSynchronously()
        await waitUntil { fixture.service.hasPendingStop }
        XCTAssertEqual(observedStates.last, false)

        fixture.service.resumePendingStop(with: .cancelled)
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testDefensiveBusyAdmissionDoesNotOpenAnotherPreparationModal() throws {
        let service = FakeChatVoiceInputService()
        let lifecycleController = VoiceInputLifecycleController(service: service)
        let fixture = try makeFixture(service: service, lifecycleController: lifecycleController)
        XCTAssertEqual(service.admitPreparation(), .initiated)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))

        XCTAssertEqual(service.prepareCallCount, 0)
        XCTAssertEqual(fixture.coordinator.phase, .idle)
        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertNil(fixture.coordinator.activeSource)
        XCTAssertFalse(fixture.coordinator.isSourceHeld)
        XCTAssertEqual(
            fixture.coordinator.notice?.message,
            ChatVoiceInputCoordinator.voiceInputPreparationBusyMessage
        )
    }

    func testNavigationCancelsHiddenWarmupAndOtherComposerRetriesAfterLateCleanup() async throws {
        let service = FakeChatVoiceInputService()
        service.setSuspendsPrepare(true)
        service.setIgnoresPreparationCancellation(true)
        let lifecycleController = VoiceInputLifecycleController(service: service)
        let first = try makeFixture(service: service, lifecycleController: lifecycleController)
        let second = try makeFixture(service: service, lifecycleController: lifecycleController)

        XCTAssertTrue(first.coordinator.physicalPress(.mouse))
        await waitUntil { service.hasPendingPrepare }
        await waitForCacheLoading(first)
        XCTAssertTrue(first.coordinator.physicalRelease(.mouse))

        first.coordinator.composerDidDisappear()

        XCTAssertNil(first.coordinator.modelModalState)
        XCTAssertFalse(lifecycleController.isComposerInteractionLocked)
        XCTAssertFalse(second.coordinator.isVoiceInputOwnedElsewhere)

        XCTAssertTrue(second.coordinator.physicalPress(.keyboard))
        XCTAssertEqual(
            second.coordinator.notice?.message,
            ChatVoiceInputCoordinator.voiceInputPreparationBusyMessage
        )
        XCTAssertNil(second.coordinator.modelModalState)
        XCTAssertEqual(service.beginRecognitionCallCount, 0)
        XCTAssertFalse(second.coordinator.physicalRelease(.keyboard))

        service.resumePendingPrepare()
        await waitUntil { first.coordinator.preparationTask == nil }

        XCTAssertEqual(first.coordinator.phase, .ready)
        XCTAssertTrue(first.coordinator.modelIsReady)
        XCTAssertFalse(first.announcements.contains("Voice model setup cancelled"))

        XCTAssertTrue(second.coordinator.physicalPress(.mouse))
        await waitUntil { second.coordinator.phase == .recording }
        XCTAssertEqual(service.beginRecognitionCallCount, 1)
        XCTAssertTrue(second.coordinator.physicalRelease(.mouse, forced: true))
        await waitUntil { second.coordinator.phase == .ready }
    }

    func testLifecycleTeardownCancelsHiddenCacheWarmupBeforeAsyncShutdown() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)

        fixture.lifecycleController.teardownSynchronously()

        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertFalse(fixture.lifecycleController.isComposerInteractionLocked)
        XCTAssertEqual(fixture.service.admitPreparation(), .busy)

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.preparationTask == nil }

        XCTAssertEqual(fixture.coordinator.phase, .idle)
        XCTAssertEqual(fixture.service.admitPreparation(), .initiated)
    }

    func testForcedStopDuringStartingCommitsBufferedFinalTranscriptSynchronously() async throws {
        let fixture = try makeFixture(text: "Draft")
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)
        fixture.service.setSuspendsCancel(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingBegin }
        fixture.service.emitPartial("first partial")
        fixture.service.emitPartial("latest partial")
        fixture.service.emitStopped(VoiceInputRecognitionResult(
            transcript: "  final\nanswer  ",
            termination: .committed,
            error: nil
        ))
        await waitUntil { fixture.coordinator.pendingStartupRecognitionUpdates.count == 3 }

        fixture.coordinator.forceStopAndCommit(reason: "Dictation stopped because the window changed.")

        XCTAssertEqual(fixture.currentMarkdown, "Draft final answer")
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)
        XCTAssertTrue(fixture.coordinator.pendingStartupRecognitionUpdates.isEmpty)
        XCTAssertEqual(fixture.coordinator.phase, .cleanup)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.service.hasPendingCancel }
        fixture.service.resumePendingCancel()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
    }

    func testTerminationDuringStartingCommitsLatestBufferedPartialSynchronously() async throws {
        let fixture = try makeFixture(text: "Draft")
        markModelReady(fixture)
        fixture.service.setSuspendsBegin(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingBegin }
        fixture.service.emitPartial("first partial")
        fixture.service.emitPartial(" latest\npartial ")
        fixture.service.emitStopped(VoiceInputRecognitionResult(
            transcript: " \n\t ",
            termination: .committed,
            error: nil
        ))
        await waitUntil { fixture.coordinator.pendingStartupRecognitionUpdates.count == 3 }

        fixture.lifecycleController.teardownSynchronously()

        XCTAssertEqual(fixture.currentMarkdown, "Draft latest partial")
        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)
        XCTAssertTrue(fixture.coordinator.pendingStartupRecognitionUpdates.isEmpty)
        XCTAssertEqual(fixture.coordinator.phase, .cleanup)

        fixture.service.resumePendingBegin()
        await waitUntil { fixture.service.cancelRecognitionCallCount == 1 }
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertEqual(fixture.flushCount, 1)
        XCTAssertNil(fixture.coordinator.provisionalSession)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }

    func testOtherComposerCannotDisplaceRecordingCoordinatorBeforeTermination() async throws {
        let service = FakeChatVoiceInputService()
        let lifecycleController = VoiceInputLifecycleController(service: service)
        let first = try makeFixture(service: service, lifecycleController: lifecycleController)
        let second = try makeFixture(service: service, lifecycleController: lifecycleController)

        await startRecording(first, source: .mouse)
        service.emitPartial("kept speech")
        await waitUntil { first.currentMarkdown == "Draft kept speech" }

        XCTAssertTrue(second.coordinator.physicalPress(.keyboard))
        XCTAssertTrue(second.coordinator.isVoiceInputOwnedElsewhere)
        XCTAssertFalse(second.coordinator.isButtonEnabled)
        XCTAssertEqual(
            second.coordinator.notice?.message,
            ChatVoiceInputCoordinator.voiceInputOwnedElsewhereMessage
        )
        XCTAssertFalse(service.hasPendingBegin)
        XCTAssertTrue(lifecycleController.isComposerInteractionLocked)

        lifecycleController.teardownSynchronously()

        XCTAssertEqual(first.currentMarkdown, "Draft kept speech")
        XCTAssertEqual(first.flushCount, 1)
        XCTAssertNil(first.coordinator.provisionalSession)
        XCTAssertEqual(second.flushCount, 0)
        XCTAssertNil(second.coordinator.provisionalSession)
        XCTAssertEqual(service.shutdownCaptureCallCount, 1)

        await waitUntil { first.coordinator.phase == .ready }
        XCTAssertEqual(second.coordinator.phase, .idle)
        XCTAssertEqual(service.cancelRecognitionCallCount, 0)
        XCTAssertTrue(first.coordinator.physicalRelease(.mouse))
        XCTAssertFalse(second.coordinator.physicalRelease(.keyboard))
    }
}
