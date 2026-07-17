import XCTest

@testable import Alveary

@MainActor
extension ChatVoiceInputCoordinatorTests {
    func waitForCacheLoading(
        _ fixture: ChatVoiceInputTestFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        await waitUntil({
            fixture.coordinator.phase == .preparing(message: "Loading voice model…", fraction: nil)
        }, file: file, line: line)
        XCTAssertNil(fixture.coordinator.modelModalState, file: file, line: line)
    }

    func testCacheOnlyPreparationAutoStartsLatchedAfterOrdinaryPhysicalRelease() async throws {
        for source in [ChatVoiceInputActivationSource.mouse, .keyboard] {
            let fixture = try makeFixture()
            fixture.service.setSuspendsPrepare(true)

            XCTAssertTrue(fixture.coordinator.physicalPress(source))
            await waitUntil { fixture.service.hasPendingPrepare }
            await waitForCacheLoading(fixture)

            fixture.clock.advance(by: .seconds(1))
            XCTAssertTrue(fixture.coordinator.physicalRelease(source))
            XCTAssertNotNil(fixture.coordinator.pendingPreparationActivation)

            fixture.service.resumePendingPrepare()
            await waitUntil { fixture.coordinator.phase == .recording }

            XCTAssertEqual(fixture.service.prepareCallCount, 1)
            XCTAssertEqual(fixture.service.beginRecognitionCallCount, 1)
            XCTAssertTrue(fixture.coordinator.isLatched)
            XCTAssertNil(fixture.coordinator.modelModalState)

            fixture.coordinator.accessibilityToggle()
            await waitUntil { fixture.coordinator.phase == .ready }
        }
    }

    func testCacheOnlyPreparationPreservesHeldPhysicalSource() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .recording }

        XCTAssertEqual(fixture.coordinator.activeSource, .mouse)
        XCTAssertTrue(fixture.coordinator.isSourceHeld)
        XCTAssertFalse(fixture.coordinator.isLatched)
        XCTAssertNil(fixture.coordinator.modelModalState)

        fixture.clock.advance(by: ChatVoiceInputCoordinator.holdThreshold)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testCacheOnlyPreparationAccessibilityActivationAutoStartsLatched() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsPrepare(true)

        fixture.coordinator.accessibilityToggle()
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .recording }

        XCTAssertTrue(fixture.coordinator.isLatched)
        XCTAssertNil(fixture.coordinator.modelModalState)
        fixture.coordinator.accessibilityToggle()
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testDownloadedResultForcesReadyModalWithoutObservedDownloadProgress() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.update),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([.checkingModel, .loadingModel, .ready])

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.coordinator.modelModalState == .ready }
        fixture.coordinator.receivePreparationProgress(
            .downloading(kind: .repair, fraction: 0.5),
            generation: fixture.coordinator.preparationGeneration
        )

        XCTAssertEqual(fixture.coordinator.phase, .ready)
        XCTAssertEqual(fixture.coordinator.modelModalState, .ready)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))
    }

    func testStaleDownloadProgressCannotConsumeRetriedCacheActivation() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationError(VoiceInputServiceError.modelDownload("offline"))

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil {
            guard let modalState = fixture.coordinator.modelModalState else { return false }
            if case .failed = modalState { return true }
            return false
        }
        let staleGeneration = fixture.coordinator.preparationGeneration
        fixture.coordinator.cancelModelPreparationFromModal()

        fixture.service.setPreparationError(nil)
        fixture.service.setSuspendsPrepare(true)
        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))

        fixture.coordinator.receivePreparationProgress(
            .downloading(kind: .installation, fraction: 0.5),
            generation: staleGeneration
        )

        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertNotNil(fixture.coordinator.pendingPreparationActivation)

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .recording }
        XCTAssertTrue(fixture.coordinator.isLatched)
        fixture.coordinator.accessibilityToggle()
        await waitUntil { fixture.coordinator.phase == .ready }
    }

    func testNewPermissionRequestConsumesValidatedCacheActivation() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .validatedCache,
            requestedMicrophonePermission: true
        ))
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.modelModalState == .ready }

        XCTAssertEqual(fixture.coordinator.phase, .ready)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)
    }

    func testForcedReleaseClearsCacheWarmupAutoStart() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse, forced: true))
        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
    }

    func testComposerContextChangeClearsCacheWarmupAutoStart() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)
        fixture.coordinator.updateComposerContext(ChatVoiceInputComposerContext(
            draftIdentity: "voice-test-draft",
            inputDraftRevision: 1,
            attachmentIDs: ["new-attachment"],
            workingDirectory: "/tmp/alveary-voice-tests"
        ))

        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)
        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
    }

    func testDraftGenerationChangeClearsCacheWarmupAutoStart() async throws {
        let fixture = try makeFixture(text: "Original")
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)
        reconfigureVoiceEditor(fixture, text: "Replacement", inputDraftRevision: 1)

        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)
        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertEqual(fixture.currentMarkdown, "Replacement")
    }

    func testSelectionChangeClearsCacheWarmupAutoStart() async throws {
        let fixture = try makeFixture(text: "Original")
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.keyboard))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)
        let blockID = try XCTUnwrap(fixture.editor.document.blocks.first?.id)
        fixture.editor.focus(blockID: blockID, utf16Offset: 1)

        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)
        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.keyboard))
        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.keyboard))
    }

    func testForcedComposerBlockClearsCacheWarmupAutoStart() async throws {
        let fixture = try makeFixture()
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitForCacheLoading(fixture)
        fixture.coordinator.forceStopAndCommit(
            reason: "Dictation stopped because the composer or app became inactive."
        )

        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)
        XCTAssertTrue(fixture.coordinator.releaseBarrier.contains(.mouse))
        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.phase == .ready }

        XCTAssertNil(fixture.coordinator.modelModalState)
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
        XCTAssertTrue(fixture.coordinator.physicalRelease(.mouse))
    }

    func testRepairProgressPromotesHiddenWarmupToBlockingModal() async throws {
        let fixture = try makeFixture()
        fixture.service.setPreparationResult(VoiceInputPreparationResult(
            source: .downloaded(.repair),
            requestedMicrophonePermission: false
        ))
        fixture.service.setPreparationProgress([
            .checkingModel,
            .loadingModel,
            .downloading(kind: .repair, fraction: 0.25),
            .loadingModel
        ])
        fixture.service.setSuspendsPrepare(true)

        XCTAssertTrue(fixture.coordinator.physicalPress(.mouse))
        await waitUntil { fixture.service.hasPendingPrepare }
        await waitUntil { fixture.coordinator.modelModalState == .preparing(.loadingModel) }

        XCTAssertNil(fixture.coordinator.pendingPreparationActivation)
        XCTAssertFalse(fixture.coordinator.physicalRelease(.mouse))

        fixture.service.resumePendingPrepare()
        await waitUntil { fixture.coordinator.modelModalState == .ready }
        XCTAssertEqual(fixture.service.beginRecognitionCallCount, 0)
    }
}
