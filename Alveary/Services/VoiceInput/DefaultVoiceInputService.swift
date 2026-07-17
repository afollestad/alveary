import Foundation

actor DefaultVoiceInputService: VoiceInputService {
    let permissionProvider: any VoiceInputPermissionProviding
    let modelRepository: any VoiceInputModelRepository
    let inferenceEngine: any VoiceInputInferenceEngine
    private let audioCaptureFactory: VoiceInputAudioCaptureFactory
    private let memoryPressureMonitor: any VoiceInputMemoryPressureMonitoring
    private let architectureCheck: VoiceInputArchitectureCheck
    nonisolated let captureSlot = VoiceInputCaptureSlot()
    nonisolated let suddenTerminationLease: VoiceInputSuddenTerminationLease
    nonisolated let preparationBroadcast = VoiceInputPreparationBroadcast()

    var modelLoaded = false {
        didSet { preparationBroadcast.setModelIsReady(modelLoaded) }
    }
    private var memoryPressureMonitoringStarted = false
    var generation: UInt64 = 0
    var activeRecognition: ActiveRecognition?
    var deferredUnpinnedModelCleanupPending = false
    var memoryPressureUnloadPending = false
    private var completedRecognition: (VoiceInputRecognitionSession, VoiceInputRecognitionResult)?
    private var completionWaiters: [UUID: [CheckedContinuation<VoiceInputRecognitionResult, Never>]] = [:]
    private var lifecycleOperationInProgress = false
    private var lifecycleWaiters: [CheckedContinuation<Void, Never>] = []
    init(
        modelsDirectory: URL = SessionComponent.appSupportDirectory
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true),
        cacheOwnershipDirectory: URL = SessionComponent.appSupportDirectory
    ) {
        let permissionProvider = AVCaptureVoiceInputPermissionProvider()
        let repository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: cacheOwnershipDirectory
        )
        let inferenceEngine = FluidVoiceInputInferenceEngine()
        let memoryPressureMonitor = DispatchMemoryPressureMonitor()
        let suddenTerminationController = ProcessSuddenTerminationController()
        self.permissionProvider = permissionProvider
        self.modelRepository = repository
        self.inferenceEngine = inferenceEngine
        self.audioCaptureFactory = { DefaultVoiceInputAudioCapture() }
        self.memoryPressureMonitor = memoryPressureMonitor
        self.architectureCheck = isVoiceInputArchitectureSupported
        self.suddenTerminationLease = VoiceInputSuddenTerminationLease(controller: suddenTerminationController)
    }

    init(
        permissionProvider: any VoiceInputPermissionProviding,
        modelRepository: any VoiceInputModelRepository,
        inferenceEngine: any VoiceInputInferenceEngine,
        audioCaptureFactory: @escaping VoiceInputAudioCaptureFactory,
        suddenTerminationController: any VoiceInputSuddenTerminationControlling,
        memoryPressureMonitor: any VoiceInputMemoryPressureMonitoring,
        architectureCheck: @escaping VoiceInputArchitectureCheck = isVoiceInputArchitectureSupported
    ) {
        self.permissionProvider = permissionProvider
        self.modelRepository = modelRepository
        self.inferenceEngine = inferenceEngine
        self.audioCaptureFactory = audioCaptureFactory
        self.memoryPressureMonitor = memoryPressureMonitor
        self.architectureCheck = architectureCheck
        self.suddenTerminationLease = VoiceInputSuddenTerminationLease(controller: suddenTerminationController)
    }

    func beginRecognition(
        attempt: VoiceInputRecognitionAttempt,
        onUpdate: @escaping VoiceInputRecognitionUpdateHandler
    ) async throws -> VoiceInputRecognitionSession {
        try installStartupCancellation(for: attempt)
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard !attempt.cancelled else { throw VoiceInputServiceError.recognitionSessionExpired }
        guard architectureCheck() else { throw VoiceInputServiceError.unsupportedArchitecture }
        guard modelLoaded else { throw VoiceInputServiceError.modelLoad("The voice model has not been prepared.") }
        try await ensureVoiceInputMicrophonePermission(permissionProvider: permissionProvider, canRequestAccess: false)
        guard activeRecognition == nil else { throw VoiceInputServiceError.alreadyRecording }

        let recognitionGeneration = try await prepareRecognitionGeneration(attempt: attempt)
        let session = VoiceInputRecognitionSession()
        let capture = audioCaptureFactory()
        let finalizationGate = VoiceInputRecognitionFinalizationGate()
        activeRecognition = ActiveRecognition(
            session: session,
            generation: recognitionGeneration,
            capture: capture,
            finalizationGate: finalizationGate,
            onUpdate: onUpdate
        )
        completedRecognition = nil

        do {
            let started = try captureSlot.start(
                capture,
                context: VoiceInputCaptureSlot.StartContext(
                    attemptID: attempt.id,
                    session: session,
                    generation: recognitionGeneration,
                    finalizationGate: finalizationGate
                ),
                onAdmission: {
                    suddenTerminationLease.acquire()
                },
                operation: {
                    try capture.start(generation: recognitionGeneration) { [weak self] event in
                        await self?.handleCaptureEvent(event, session: session, generation: recognitionGeneration)
                    }
                }
            )
            guard started else { throw VoiceInputServiceError.recognitionSessionExpired }
            guard !attempt.cancelled else { throw VoiceInputServiceError.recognitionSessionExpired }
        } catch {
            captureSlot.clear(capture)
            activeRecognition = nil
            suddenTerminationLease.release()
            await cancelAndRecoverLoadedInference()
            throw mappedVoiceInputError(error, fallback: .audioCapture(error.localizedDescription))
        }
        return session
    }

    func stopRecognition(_ session: VoiceInputRecognitionSession) async -> VoiceInputRecognitionResult {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        if let completedRecognition, completedRecognition.0 == session {
            return completedRecognition.1
        }
        guard var active = activeRecognition, active.session == session else {
            return VoiceInputRecognitionResult(
                transcript: nil,
                termination: .inferenceFailure,
                error: .recognitionSessionExpired
            )
        }
        if active.finalizing {
            return await waitForCompletion(of: session)
        }

        active.finalizing = true
        active.deliverPartials = false
        activeRecognition = active
        active.capture.shutdownSynchronously()
        await active.capture.stopAndDrain()

        if let completedRecognition, completedRecognition.0 == session {
            return completedRecognition.1
        }
        guard let current = activeRecognition, current.session == session else {
            return VoiceInputRecognitionResult(
                transcript: nil,
                termination: .inferenceFailure,
                error: .recognitionSessionExpired
            )
        }
        if let failure = current.pendingTerminalFailure {
            return await finishRecognition(current, after: failure)
        }
        return await finishRecognition(current, terminationOnSuccess: .committed)
    }

    func shutdown() async {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        memoryPressureMonitor.stop()
        memoryPressureMonitoringStarted = false
        memoryPressureUnloadPending = false
        modelLoaded = false
        generation &+= 1
        if var active = activeRecognition {
            if active.finalizing {
                _ = await waitForCompletion(of: active.session)
            } else {
                active.finalizing = true
                active.deliverPartials = false
                activeRecognition = active
                captureSlot.cancelSynchronously(for: active.session)
                await active.capture.stopAndDiscard()
                _ = await inferenceEngine.cancelAndReset()
                if let current = activeRecognition, current.session == active.session {
                    let result = VoiceInputRecognitionResult(
                        transcript: usableVoiceInputTranscript(current.latestPartial),
                        termination: .shutdown,
                        error: nil
                    )
                    completeRecognition(session: current.session, capture: current.capture, result: result)
                }
            }
        }
        modelLoaded = false
        await inferenceEngine.cleanup()
        await removeDeferredUnpinnedModelsAfterInferenceCleanup()
        suddenTerminationLease.release()
    }

    private func handleCaptureEvent(
        _ event: VoiceInputCaptureEvent,
        session: VoiceInputRecognitionSession,
        generation: UInt64
    ) async {
        guard let active = activeRecognition,
              active.session == session,
              active.generation == generation,
              !active.finalizationGate.cancellationWasRequested else {
            return
        }

        switch event {
        case .audio(let transfer):
            await processAudio(transfer, session: session, generation: generation)
        case .failed(let error):
            await finishAfterCaptureFailure(error, session: session, generation: generation)
        }
    }

    private func processAudio(
        _ transfer: VoiceInputPCMTransfer,
        session: VoiceInputRecognitionSession,
        generation: UInt64
    ) async {
        do {
            let partial = try await inferenceEngine.process(transfer)
            guard var active = activeRecognition,
                  active.session == session,
                  active.generation == generation,
                  !active.finalizationGate.cancellationWasRequested,
                  let usable = usableVoiceInputTranscript(partial) else {
                return
            }
            let changed = usable != active.latestPartial
            active.latestPartial = usable
            activeRecognition = active
            if changed, active.deliverPartials {
                active.onUpdate(.partial(session: session, text: usable))
            }
        } catch {
            await finishAfterCaptureFailure(
                .inference(error.localizedDescription),
                session: session,
                generation: generation,
                inferenceFailure: true
            )
        }
    }

    private func finishAfterCaptureFailure(
        _ error: VoiceInputServiceError,
        session: VoiceInputRecognitionSession,
        generation: UInt64,
        inferenceFailure: Bool = false
    ) async {
        guard var active = activeRecognition,
              active.session == session,
              active.generation == generation,
              !active.finalizationGate.cancellationWasRequested else {
            return
        }
        let failure = ActiveRecognition.TerminalFailure(
            error: error,
            inferenceFailure: inferenceFailure
        )
        if active.finalizing {
            guard active.pendingTerminalFailure == nil else { return }
            active.pendingTerminalFailure = failure
            activeRecognition = active
            active.onUpdate(.captureFailed(session: session, error: error))
            return
        }
        active.finalizing = true
        active.pendingTerminalFailure = failure
        active.deliverPartials = false
        activeRecognition = active
        active.onUpdate(.captureFailed(session: session, error: error))
        active.capture.shutdownSynchronously()

        let result = await finishRecognition(active, after: failure)
        active.onUpdate(.stopped(session: session, result: result))
    }

    private func finishRecognition(
        _ active: ActiveRecognition,
        after failure: ActiveRecognition.TerminalFailure
    ) async -> VoiceInputRecognitionResult {
        guard failure.inferenceFailure else {
            return await finishRecognition(
                active,
                terminationOnSuccess: .captureFailure,
                forcedError: failure.error
            )
        }
        await cancelAndRecoverLoadedInference()
        let result = VoiceInputRecognitionResult(
            transcript: usableVoiceInputTranscript(active.latestPartial),
            termination: .inferenceFailure,
            error: failure.error
        )
        completeRecognition(session: active.session, capture: active.capture, result: result)
        return result
    }

    private func finishRecognition(
        _ active: ActiveRecognition,
        terminationOnSuccess: VoiceInputRecognitionResult.Termination,
        forcedError: VoiceInputServiceError? = nil
    ) async -> VoiceInputRecognitionResult {
        guard active.finalizationGate.claimFinish() else {
            generation &+= 1
            await cancelAndRecoverLoadedInference()
            completeRecognition(session: active.session, capture: active.capture, result: .cancelled)
            return .cancelled
        }
        let wasModelLoaded = modelLoaded
        modelLoaded = false
        let result: VoiceInputRecognitionResult
        do {
            let finalization = try await inferenceEngine.finishAndReset()
            modelLoaded = await cleanupVoiceInputInferenceIfNeeded(
                inferenceEngine,
                isReusable: finalization.isReusable
            ) && wasModelLoaded
            result = VoiceInputRecognitionResult(
                transcript: usableVoiceInputTranscript(finalization.transcript) ?? usableVoiceInputTranscript(active.latestPartial),
                termination: terminationOnSuccess,
                error: forcedError
            )
        } catch {
            modelLoaded = await recoverVoiceInputInference(
                inferenceEngine,
                after: error,
                wasLoaded: wasModelLoaded
            )
            result = VoiceInputRecognitionResult(
                transcript: usableVoiceInputTranscript(active.latestPartial),
                termination: .inferenceFailure,
                error: .inference(error.localizedDescription)
            )
        }
        completeRecognition(session: active.session, capture: active.capture, result: result)
        return result
    }

    private func completeRecognition(
        session: VoiceInputRecognitionSession,
        capture: any VoiceInputAudioCapturing,
        result: VoiceInputRecognitionResult
    ) {
        if activeRecognition?.session == session {
            activeRecognition = nil
        }
        captureSlot.clear(capture)
        completedRecognition = (session, result)
        suddenTerminationLease.release()
        let waiters = completionWaiters.removeValue(forKey: session.id) ?? []
        for waiter in waiters {
            waiter.resume(returning: result)
        }
        schedulePendingMemoryPressureUnloadIfNeeded()
    }

    private func waitForCompletion(of session: VoiceInputRecognitionSession) async -> VoiceInputRecognitionResult {
        if let completedRecognition, completedRecognition.0 == session {
            return completedRecognition.1
        }
        return await withCheckedContinuation { continuation in
            completionWaiters[session.id, default: []].append(continuation)
        }
    }

    func acquireLifecycleOperation() async {
        if !lifecycleOperationInProgress {
            lifecycleOperationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            lifecycleWaiters.append(continuation)
        }
    }

    func tryAcquireLifecycleOperation() -> Bool {
        guard !lifecycleOperationInProgress else { return false }
        lifecycleOperationInProgress = true
        return true
    }

    func releaseLifecycleOperation() {
        if lifecycleWaiters.isEmpty {
            lifecycleOperationInProgress = false
        } else {
            lifecycleWaiters.removeFirst().resume()
        }
    }

    deinit {
        captureSlot.terminateSynchronously()
        memoryPressureMonitor.stop()
        suddenTerminationLease.release()
    }
}

extension DefaultVoiceInputService {
    func isVoiceInputArchitectureAvailable() -> Bool {
        architectureCheck()
    }

    func startMemoryPressureMonitoringIfNeeded() {
        guard !memoryPressureMonitoringStarted else { return }
        memoryPressureMonitoringStarted = true
        memoryPressureMonitor.start { [weak self, preparationBroadcast] in
            guard let observedModelGeneration = preparationBroadcast.readyModelGenerationForMemoryPressure() else {
                return
            }
            Task {
                await self?.handleMemoryPressure(observedModelGeneration: observedModelGeneration)
            }
        }
    }

    nonisolated func cancelRecognition(_ session: VoiceInputRecognitionSession) async {
        captureSlot.cancelSynchronously(for: session)
        await cancelRecognitionAfterSynchronousCancellation(session)
    }

    private func cancelRecognitionAfterSynchronousCancellation(_ session: VoiceInputRecognitionSession) async {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }

        guard var active = activeRecognition, active.session == session else { return }
        if active.finalizing {
            _ = await waitForCompletion(of: session)
            return
        }
        active.finalizing = true
        active.deliverPartials = false
        generation &+= 1
        activeRecognition = active
        await active.capture.stopAndDiscard()
        await cancelAndRecoverLoadedInference()
        completeRecognition(session: session, capture: active.capture, result: .cancelled)
    }

    private nonisolated func installStartupCancellation(for attempt: VoiceInputRecognitionAttempt) throws {
        let attemptID = attempt.id
        guard attempt.installCancellationHandler({ [captureSlot] in
            captureSlot.cancelStartupSynchronously(attemptID: attemptID)
        }) else {
            throw VoiceInputServiceError.recognitionSessionExpired
        }
    }

    private func prepareRecognitionGeneration(attempt: VoiceInputRecognitionAttempt) async throws -> UInt64 {
        guard !attempt.cancelled else {
            throw VoiceInputServiceError.recognitionSessionExpired
        }
        generation &+= 1
        let recognitionGeneration = generation
        guard captureSlot.reserve(attemptID: attempt.id, generation: recognitionGeneration) else {
            throw VoiceInputServiceError.recognitionSessionExpired
        }
        guard !attempt.cancelled else {
            captureSlot.clearReservation(attemptID: attempt.id, generation: recognitionGeneration)
            throw VoiceInputServiceError.recognitionSessionExpired
        }
        let wasModelLoaded = modelLoaded
        modelLoaded = false
        do {
            try await inferenceEngine.reset()
            modelLoaded = wasModelLoaded
            return recognitionGeneration
        } catch {
            captureSlot.clearReservation(attemptID: attempt.id, generation: recognitionGeneration)
            _ = await cleanupVoiceInputInferenceIfNeeded(inferenceEngine, isReusable: false)
            throw mappedVoiceInputError(
                error,
                fallback: .inference(error.localizedDescription)
            )
        }
    }

    private func cancelAndRecoverLoadedInference() async {
        let wasModelLoaded = modelLoaded
        modelLoaded = false
        modelLoaded = await cancelAndRecoverVoiceInputInference(inferenceEngine) && wasModelLoaded
    }
}
