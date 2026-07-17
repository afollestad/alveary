@testable import Alveary
import XCTest

@MainActor
final class VoiceInputInferenceSerializationTests: XCTestCase {
    func testReentrantManagerOperationsRemainSerialized() async throws {
        let manager = ReentrantStreamingManagerFake()
        let engine = FluidVoiceInputInferenceEngine(manager: manager, managerFactory: { manager })
        let first = makeVoiceInputPCMTransfer()
        let second = makeVoiceInputPCMTransfer()

        async let firstResult = engine.process(first)
        async let secondResult = engine.process(second)
        _ = try await (firstResult, secondResult)

        let maximum = await manager.maximumConcurrentOperations
        XCTAssertEqual(maximum, 1)
    }

    func testSuccessfulFinalTranscriptSurvivesResetFailure() async throws {
        let manager = ResetFailingFinalManagerFake()
        let engine = FluidVoiceInputInferenceEngine(manager: manager, managerFactory: { manager })

        let final = try await engine.finishAndReset()

        XCTAssertEqual(final.transcript, "newer final")
        XCTAssertFalse(final.isReusable)
        let resetCount = await manager.resetCount
        let cancelAndResetCount = await manager.cancelAndResetCount
        XCTAssertEqual(resetCount, 1)
        XCTAssertEqual(cancelAndResetCount, 1)
    }
}

private actor ReentrantStreamingManagerFake: VoiceInputStreamingManaging {
    private(set) var maximumConcurrentOperations = 0
    private var concurrentOperations = 0

    func loadModels(from directory: URL) async throws {}

    func reset() async throws {}

    func appendAndProcess(_ transfer: VoiceInputPCMTransfer) async throws -> String {
        concurrentOperations += 1
        maximumConcurrentOperations = max(maximumConcurrentOperations, concurrentOperations)
        try await Task.sleep(for: .milliseconds(20))
        concurrentOperations -= 1
        return "partial"
    }

    func finish() async throws -> String {
        "final"
    }

    func cancelAndReset() async -> Bool { true }

    func cleanup() async {}
}

private actor ResetFailingFinalManagerFake: VoiceInputStreamingManaging {
    private(set) var resetCount = 0
    private(set) var cancelAndResetCount = 0

    func loadModels(from directory: URL) async throws {}

    func reset() async throws {
        resetCount += 1
        throw VoiceInputInferenceFakeError(message: "reset failed")
    }

    func appendAndProcess(_ transfer: VoiceInputPCMTransfer) async throws -> String {
        "partial"
    }

    func finish() async throws -> String {
        "newer final"
    }

    func cancelAndReset() async -> Bool {
        cancelAndResetCount += 1
        return false
    }

    func cleanup() async {}
}
