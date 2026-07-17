import Foundation

extension DefaultVoiceInputService {
    nonisolated func admitPreparation(requiringPreparation: Bool) -> VoiceInputPreparationAdmission {
        preparationBroadcast.admitPreparation(requiringPreparation: requiringPreparation)
    }

    func prepare(progress: @escaping VoiceInputPreparationProgressHandler) async throws -> VoiceInputPreparationResult {
        guard preparationBroadcast.beginParticipant() else {
            throw VoiceInputServiceError.modelPreparationBusy
        }
        let progressToken = preparationBroadcast.addObserver(progress)
        defer {
            preparationBroadcast.removeObserver(progressToken)
            preparationBroadcast.endParticipant()
        }
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        return try await performPreparation()
    }

    private func performPreparation() async throws -> VoiceInputPreparationResult {
        try Task.checkCancellation()
        preparationBroadcast.begin()
        defer { preparationBroadcast.end() }
        guard isVoiceInputArchitectureAvailable() else { throw VoiceInputServiceError.unsupportedArchitecture }

        preparationBroadcast.publish(.checkingPermission)
        let requestedMicrophonePermission = try await ensureVoiceInputMicrophonePermission(
            permissionProvider: permissionProvider,
            canRequestAccess: true
        )
        try Task.checkCancellation()
        if publishReadyIfModelLoaded() {
            return VoiceInputPreparationResult(
                source: .inMemory,
                requestedMicrophonePermission: requestedMicrophonePermission
            )
        }

        let reportProgress: VoiceInputPreparationProgressHandler = { [preparationBroadcast] update in
            preparationBroadcast.publish(update)
        }
        let prepared = try await modelRepository.prepareModel(mode: .normal, progress: reportProgress)
        try Task.checkCancellation()
        let finalSource = try await loadVoiceInputModelsWithRepair(
            prepared: prepared,
            inferenceEngine: inferenceEngine,
            modelRepository: modelRepository,
            progress: reportProgress,
            broadcast: preparationBroadcast
        )
        if Task.isCancelled {
            try await throwVoiceInputModelLoadCancellation(afterCleaning: inferenceEngine)
        }

        deferredUnpinnedModelCleanupPending = true
        modelLoaded = true
        startMemoryPressureMonitoringIfNeeded()
        preparationBroadcast.publish(.ready)
        return VoiceInputPreparationResult(
            source: preparationSource(for: finalSource),
            requestedMicrophonePermission: requestedMicrophonePermission
        )
    }

    func publishReadyIfModelLoaded() -> Bool {
        guard modelLoaded else { return false }
        startMemoryPressureMonitoringIfNeeded()
        preparationBroadcast.publish(.ready)
        return true
    }

    private func preparationSource(for source: VoiceInputPreparedModel.Source) -> VoiceInputPreparationSource {
        switch source {
        case .validatedCache:
            return .validatedCache
        case .downloaded(let kind):
            return .downloaded(kind)
        }
    }
}
