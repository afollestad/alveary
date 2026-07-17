import Foundation

extension ChatVoiceInputCoordinator {
    static var isSupportedArchitecture: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    func activateReadyVoiceInputOrPrepare(activation: ChatVoiceInputPreparationActivation) {
        guard preparationTask == nil else { return }
        switch service.admitPreparation() {
        case .ready:
            modelIsReady = true
            beginRecognition()
        case .initiated:
            pendingPreparationActivation = ChatVoiceInputPendingActivation(
                activation: activation,
                editorDraftIdentity: editorHandle.draftIdentity,
                editorDraftGeneration: editorHandle.draftGeneration,
                composerContext: composerContext
            )
            prepareVoiceInput()
        case .busy:
            pendingPreparationActivation = nil
            clearPhysicalPress()
            phase = modelIsReady ? .ready : .idle
            present(message: Self.voiceInputPreparationBusyMessage, severity: .info)
        }
    }

    func prepareVoiceInput() {
        guard preparationTask == nil else {
            return
        }
        phase = .preparing(message: "Checking microphone access…", fraction: nil)
        notice = nil
        modelModalState = nil
        lifecycleController.setActiveComposerSink(self)
        let service = service
        preparationGeneration &+= 1
        let generation = preparationGeneration
        preparationCancellationRequested = false
        shouldAnnouncePreparationCancellation = false
        let delivery = ChatVoiceInputCallbackDelivery(coordinator: self)
        preparationTask = Task { [weak self] in
            do {
                let result = try await service.prepare { progress in
                    delivery.deliverPreparation(progress, generation: generation)
                }
                self?.finishPreparation(generation: generation, result: result, error: nil)
            } catch {
                self?.finishPreparation(generation: generation, result: nil, error: error)
            }
        }
    }

    func prepareVoiceInputAfterReadinessInvalidation() {
        guard service.admitPreparation(requiringPreparation: true) == .initiated else {
            pendingPreparationActivation = nil
            clearPhysicalPress()
            phase = modelIsReady ? .ready : .idle
            present(message: Self.voiceInputPreparationBusyMessage, severity: .info)
            return
        }
        pendingPreparationActivation = nil
        prepareVoiceInput()
    }

    func receivePreparationProgress(_ progress: VoiceInputPreparationProgress, generation: UInt64) {
        guard generation == preparationGeneration,
              preparationTask != nil,
              !preparationCancellationRequested else {
            return
        }
        switch progress {
        case .checkingPermission:
            phase = .preparing(message: "Checking microphone access…", fraction: nil)
        case .checkingModel:
            phase = .preparing(message: "Checking voice model…", fraction: nil)
        case .downloading(let kind, let fraction):
            pendingPreparationActivation = nil
            clearPhysicalPress()
            let action = switch kind {
            case .installation: "Downloading"
            case .update: "Updating"
            case .repair: "Repairing"
            }
            phase = .preparing(message: "\(action) voice model (about 600 MB)…", fraction: fraction)
            modelModalState = .preparing(progress)
        case .loadingModel:
            phase = .preparing(message: "Loading voice model…", fraction: nil)
            if modelModalState != nil {
                modelModalState = .preparing(progress)
            }
        case .ready:
            // The service publishes `.ready` immediately before `prepare` returns.
            // Keep the modal non-dismissible until the owning task has actually
            // completed so Continue cannot race the remaining preparation cleanup.
            break
        }
    }

    func finishPreparation(
        generation: UInt64,
        result: VoiceInputPreparationResult?,
        error: Error?
    ) {
        guard generation == preparationGeneration else {
            return
        }
        preparationTask = nil
        let cancellationWasRequested = preparationCancellationRequested
        let announcesCancellation = shouldAnnouncePreparationCancellation
        preparationCancellationRequested = false
        shouldAnnouncePreparationCancellation = false
        if cancellationWasRequested {
            finishCancelledPreparation(result: result, announcesCancellation: announcesCancellation)
            return
        }
        if let error {
            finishFailedPreparation(error)
            return
        }
        guard let result else {
            finishPreparationWithoutResult()
            return
        }
        finishSuccessfulPreparation(result)
    }

    private func finishCancelledPreparation(
        result: VoiceInputPreparationResult?,
        announcesCancellation: Bool
    ) {
        pendingPreparationActivation = nil
        clearPhysicalPress()
        modelModalState = nil
        modelIsReady = result != nil
        phase = modelIsReady ? .ready : .idle
        lifecycleController.clearActiveComposerSink(self)
        if announcesCancellation {
            announce("Voice model setup cancelled")
        }
    }

    private func finishFailedPreparation(_ error: Error) {
        pendingPreparationActivation = nil
        clearPhysicalPress()
        modelIsReady = false
        phase = .idle
        if error is CancellationError {
            modelModalState = nil
            lifecycleController.clearActiveComposerSink(self)
            return
        }
        presentModelPreparationFailure(error)
    }

    private func presentModelPreparationFailure(_ error: Error) {
        let failureNotice = voiceInputNotice(for: error)
        notice = nil
        modelModalState = .failed(
            message: failureNotice.message,
            recovery: failureNotice.recovery == .microphoneSettings ? .microphoneSettings : nil
        )
        announce(failureNotice.message)
    }

    private func finishPreparationWithoutResult() {
        pendingPreparationActivation = nil
        clearPhysicalPress()
        modelIsReady = false
        phase = .idle
        modelModalState = .failed(
            message: "The local voice model could not be loaded. Try again to repair it.",
            recovery: nil
        )
    }

    private func finishSuccessfulPreparation(_ result: VoiceInputPreparationResult) {
        modelIsReady = true
        phase = .ready
        notice = nil
        if result.requestedMicrophonePermission || result.source.requiresFreshActivation {
            pendingPreparationActivation = nil
            clearPhysicalPress()
            modelModalState = .ready
            announce("Voice input is ready")
            return
        }

        modelModalState = nil
        guard let activation = pendingPreparationActivation,
              pendingPreparationActivationIsValid(activation) else {
            pendingPreparationActivation = nil
            clearPhysicalPress()
            lifecycleController.clearActiveComposerSink(self)
            return
        }
        pendingPreparationActivation = nil
        beginRecognition()
    }

    func cancelModelPreparationFromModal() {
        guard let modelModalState else {
            return
        }
        switch modelModalState {
        case .preparing:
            guard preparationTask != nil,
                  !preparationCancellationRequested else {
                return
            }
            preparationCancellationRequested = true
            shouldAnnouncePreparationCancellation = true
            pendingPreparationActivation = nil
            clearPhysicalPress()
            phase = .preparing(message: "Cancelling voice model preparation…", fraction: nil)
            self.modelModalState = .cancelling
            preparationTask?.cancel()
        case .failed:
            self.modelModalState = nil
            lifecycleController.clearActiveComposerSink(self)
            announce("Voice model setup cancelled")
        case .cancelling, .ready:
            break
        }
    }

    func cancelModelPreparationForTeardown() {
        guard preparationTask != nil else {
            return
        }
        preparationCancellationRequested = true
        shouldAnnouncePreparationCancellation = false
        pendingPreparationActivation = nil
        clearPhysicalPress()
        if modelModalState != nil {
            modelModalState = .cancelling
        }
        preparationTask?.cancel()
        lifecycleController.clearActiveComposerSink(self)
    }

    func continueAfterModelPreparation() {
        guard modelModalState == .ready else {
            return
        }
        modelModalState = nil
        lifecycleController.clearActiveComposerSink(self)
    }

    private func pendingPreparationActivationIsValid(
        _ activation: ChatVoiceInputPendingActivation
    ) -> Bool {
        guard editorHandle.draftIdentity == activation.editorDraftIdentity,
            editorHandle.draftGeneration == activation.editorDraftGeneration &&
            composerContext == activation.composerContext &&
            editorHandle.canStartVoiceInput else {
            return false
        }
        switch activation.activation {
        case .accessibility:
            return activeSource == nil && !isSourceHeld
        case .physical(let source):
            if let activeSource {
                return activeSource == source && isSourceHeld
            }
            return !isSourceHeld
        }
    }

    func beginRecognition() {
        guard startupTask == nil,
              recognitionSession == nil else {
            return
        }
        guard editorHandle.canStartVoiceInput else {
            present(message: voiceInputStartUnavailableMessage, severity: .error)
            clearPhysicalPress()
            phase = modelIsReady ? .ready : .idle
            return
        }

        phase = .starting
        latestNonemptyTranscript = nil
        advanceGeneration()
        lifecycleController.setActiveComposerSink(self)
        let generation = sessionGeneration
        let startupDraftIdentity = editorHandle.draftIdentity
        let startupDraftGeneration = editorHandle.draftGeneration
        let startupComposerContext = composerContext
        acceptsPartialDelivery = true
        let service = service
        let startupLifetime = startupLifetime
        let attempt = VoiceInputRecognitionAttempt()
        startupLifetime.begin(attempt)
        let delivery = ChatVoiceInputCallbackDelivery(coordinator: self)
        startupTask = Task { [weak self] in
            do {
                let session = try await service.beginRecognition(attempt: attempt) { update in
                    delivery.deliverRecognition(update, generation: generation)
                }
                guard self?.canCompleteStartup(
                    generation: generation,
                    draftIdentity: startupDraftIdentity,
                    draftGeneration: startupDraftGeneration,
                    composerContext: startupComposerContext
                ) == true else {
                    self?.beginPendingStartupCleanup()
                    startupLifetime.invalidate()
                    await service.cancelRecognition(session)
                    self?.finishPendingStartupCleanup(generation: generation)
                    return
                }
                guard let self else { return }
                self.recognitionDidStart(session, generation: generation)
                startupLifetime.finish(attempt)
            } catch {
                startupLifetime.finish(attempt)
                guard let self else { return }
                self.recognitionDidFailToStart(error, generation: generation)
            }
        }
    }

    private func canCompleteStartup(
        generation: UInt64,
        draftIdentity: String?,
        draftGeneration: UInt64,
        composerContext: ChatVoiceInputComposerContext?
    ) -> Bool {
        sessionGeneration == generation &&
            phase == .starting &&
            editorHandle.draftIdentity == draftIdentity &&
            editorHandle.draftGeneration == draftGeneration &&
            self.composerContext == composerContext &&
            editorHandle.canStartVoiceInput
    }

    private var voiceInputStartUnavailableMessage: String {
        if !editorHandle.isMounted {
            return "The message editor is not available for dictation."
        }
        if editorHandle.hasPresentedEditorInteractionUI {
            return "Close the editor popover before dictating."
        }
        return "Place the cursor in text, or select text within one block, before dictating."
    }

    func recognitionDidStart(_ session: VoiceInputRecognitionSession, generation: UInt64) {
        guard generation == sessionGeneration else { return }
        startupTask = nil
        recognitionSession = session
        let pendingRecognitionUpdates = pendingStartupRecognitionUpdates
        pendingStartupRecognitionUpdates.removeAll()
        switch editorHandle.beginProvisionalTextReplacement() {
        case .started(let provisional):
            provisionalSession = provisional
            // BlockInputKit may establish a deterministic fallback caret while
            // beginning the transaction, so read its resulting selection here.
            insertionContext = editorHandle.insertionContext()
        case .unavailable(let reason):
            acceptsPartialDelivery = false
            startupRelease = nil
            installReleaseBarrierForHeldSource()
            startupLifetime.invalidate()
            phase = .cleanup
            present(message: unavailableSelectionMessage(reason), severity: .error)
            let service = service
            startupTask = Task { [weak self] in
                await service.cancelRecognition(session)
                guard let self else { return }
                self.finishCleanup(session: session)
            }
            return
        }

        lifecycleController.setActiveComposerSink(self)
        phase = .recording
        if activeSource == nil, startupRelease == nil {
            isLatched = true
        }
        announce("Dictation started")
        startRecordingLimit(generation: generation)

        for update in pendingRecognitionUpdates {
            receiveRecognitionUpdate(update, generation: generation)
        }
        guard recognitionSession == session, phase == .recording else {
            self.startupRelease = nil
            return
        }
        if let startupRelease {
            self.startupRelease = nil
            if startupRelease.forced || startupRelease.duration >= Self.holdThreshold {
                requestStopAndCommit()
            } else {
                isLatched = true
            }
        }
    }

    func recognitionDidFailToStart(_ error: Error, generation: UInt64) {
        guard generation == sessionGeneration else {
            finishPendingStartupCleanup(generation: generation)
            return
        }
        startupTask = nil
        acceptsPartialDelivery = false
        lifecycleController.clearActiveComposerSink(self)
        if let serviceError = error as? VoiceInputServiceError,
           serviceError == .permissionDenied || serviceError == .permissionRestricted {
            clearPhysicalPress()
            phase = modelIsReady ? .ready : .idle
            presentModelPreparationFailure(error)
            return
        }
        if case .permissionNotDetermined = error as? VoiceInputServiceError {
            modelIsReady = false
            clearPhysicalPress()
            phase = .idle
            prepareVoiceInputAfterReadinessInvalidation()
            return
        }
        if case .modelLoad = error as? VoiceInputServiceError {
            modelIsReady = false
            phase = .idle
            if hasAttemptedStartupModelReload {
                clearPhysicalPress()
                present(error: error)
            } else {
                hasAttemptedStartupModelReload = true
                clearPhysicalPress()
                prepareVoiceInputAfterReadinessInvalidation()
            }
            return
        }
        clearPhysicalPress()
        phase = modelIsReady ? .ready : .idle
        present(error: error)
    }
}

private extension VoiceInputPreparationSource {
    var requiresFreshActivation: Bool {
        switch self {
        case .downloaded:
            true
        case .inMemory, .validatedCache:
            false
        }
    }
}
