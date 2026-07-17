import Foundation

extension DefaultVoiceInputService {
    func unloadIfIdle() async {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        await unloadLoadedModelIfIdle()
    }

    func handleMemoryPressure(observedModelGeneration: UInt64) async {
        guard preparationBroadcast.isCurrentReadyModelGeneration(observedModelGeneration) else {
            return
        }
        guard tryAcquireLifecycleOperation() else {
            if activeRecognition != nil {
                memoryPressureUnloadPending = true
            }
            return
        }

        defer { releaseLifecycleOperation() }
        guard preparationBroadcast.isCurrentReadyModelGeneration(observedModelGeneration) else {
            return
        }
        await unloadLoadedModelIfIdle()
    }

    func handleDeferredMemoryPressure(observedModelGeneration: UInt64) async {
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard preparationBroadcast.isCurrentReadyModelGeneration(observedModelGeneration) else {
            return
        }
        await unloadLoadedModelIfIdle()
    }

    private func unloadLoadedModelIfIdle() async {
        guard activeRecognition == nil else {
            memoryPressureUnloadPending = true
            return
        }
        guard modelLoaded else {
            memoryPressureUnloadPending = false
            return
        }
        memoryPressureUnloadPending = false
        modelLoaded = false
        await inferenceEngine.cleanup()
        await removeDeferredUnpinnedModelsAfterInferenceCleanup()
    }

    func clearModelCache() async throws {
        guard !preparationBroadcast.isBusyForCacheClear else {
            throw VoiceInputServiceError.modelCacheBusy
        }
        await acquireLifecycleOperation()
        defer { releaseLifecycleOperation() }
        guard !preparationBroadcast.isBusyForCacheClear, activeRecognition == nil else {
            throw VoiceInputServiceError.modelCacheBusy
        }
        generation &+= 1
        memoryPressureUnloadPending = false
        if modelLoaded {
            modelLoaded = false
            await inferenceEngine.cleanup()
        }
        try await modelRepository.purgeAllModels()
        deferredUnpinnedModelCleanupPending = false
    }

    func removeDeferredUnpinnedModelsAfterInferenceCleanup() async {
        guard deferredUnpinnedModelCleanupPending else { return }
        do {
            try await modelRepository.removeUnpinnedModels()
            deferredUnpinnedModelCleanupPending = false
        } catch {
            // Keep the cleanup pending for a later idle unload or shutdown.
        }
    }

    func schedulePendingMemoryPressureUnloadIfNeeded() {
        guard memoryPressureUnloadPending else { return }
        guard let observedModelGeneration = preparationBroadcast.readyModelGenerationForMemoryPressure() else {
            if !modelLoaded {
                memoryPressureUnloadPending = false
            }
            return
        }
        memoryPressureUnloadPending = false
        Task { [weak self] in
            await self?.handleDeferredMemoryPressure(observedModelGeneration: observedModelGeneration)
        }
    }
}
