@preconcurrency import AVFoundation
@preconcurrency import CoreML
import FluidAudio
import Foundation

protocol VoiceInputStreamingManaging: Actor {
    func loadModels(from directory: URL) async throws
    func reset() async throws
    func appendAndProcess(_ transfer: VoiceInputPCMTransfer) async throws -> String
    func finish() async throws -> String
    func cancelAndReset() async -> Bool
    func cleanup() async
}

actor FluidVoiceInputStreamingManager: VoiceInputStreamingManaging {
    private let manager: StreamingUnifiedAsrManager

    init() {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = .cpuAndNeuralEngine
        manager = StreamingUnifiedAsrManager(
            configuration: configuration,
            config: UnifiedConfig(leftFrames: 70, chunkFrames: 2, rightFrames: 2),
            encoderPrecision: .int8
        )
    }

    func loadModels(from directory: URL) async throws {
        try await manager.loadModels(from: directory)
    }

    func reset() async throws {
        try await manager.reset()
    }

    func appendAndProcess(_ transfer: VoiceInputPCMTransfer) async throws -> String {
        try await manager.appendAudio(transfer.buffer)
        try await manager.processBufferedAudio()
        let partial = await manager.getPartialTranscript()
        _ = await manager.consumeTokenTimings()
        return partial
    }

    func finish() async throws -> String {
        let final = try await manager.finish()
        _ = await manager.consumeTokenTimings()
        return final
    }

    func cancelAndReset() async -> Bool {
        do {
            try await manager.reset()
            return true
        } catch {
            return false
        }
    }

    func cleanup() async {
        await manager.cleanup()
    }
}

actor FluidVoiceInputInferenceEngine: VoiceInputInferenceEngine {
    private var manager: any VoiceInputStreamingManaging
    private let managerFactory: @Sendable () -> any VoiceInputStreamingManaging
    private var operationInProgress = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        manager: any VoiceInputStreamingManaging = FluidVoiceInputStreamingManager(),
        managerFactory: @escaping @Sendable () -> any VoiceInputStreamingManaging = {
            FluidVoiceInputStreamingManager()
        }
    ) {
        self.manager = manager
        self.managerFactory = managerFactory
    }

    func loadModels(from directory: URL) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try await manager.loadModels(from: directory)
    }

    func reset() async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try await manager.reset()
    }

    func process(_ buffer: VoiceInputPCMTransfer) async throws -> String {
        await acquireOperation()
        defer { releaseOperation() }
        return try await manager.appendAndProcess(buffer)
    }

    func finishAndReset() async throws -> VoiceInputInferenceFinalization {
        await acquireOperation()
        defer { releaseOperation() }
        let final: String
        do {
            final = try await manager.finish()
        } catch {
            let isReusable = await manager.cancelAndReset()
            throw VoiceInputInferenceOperationError(
                message: error.localizedDescription,
                isReusable: isReusable
            )
        }
        let isReusable: Bool
        do {
            try await manager.reset()
            isReusable = true
        } catch {
            // The transcript has already finalized successfully. Preserve it
            // while making one best-effort reset before the next lease.
            isReusable = await manager.cancelAndReset()
        }
        return VoiceInputInferenceFinalization(transcript: final, isReusable: isReusable)
    }

    func cancelAndReset() async -> Bool {
        await acquireOperation()
        defer { releaseOperation() }
        return await manager.cancelAndReset()
    }

    func cleanup() async {
        await acquireOperation()
        defer { releaseOperation() }
        await manager.cleanup()
        manager = managerFactory()
    }

    private func acquireOperation() async {
        if !operationInProgress {
            operationInProgress = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        if operationWaiters.isEmpty {
            operationInProgress = false
        } else {
            operationWaiters.removeFirst().resume()
        }
    }
}
