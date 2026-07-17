import XCTest

@testable import Alveary

@MainActor
extension DefaultVoiceInputServiceTests {
    func testCaptureFailureObservedDuringManualDrainIsCommittedAsFailure() async throws {
        let inference = VoiceInputInferenceFake()
        await inference.setProcessOutputs(["usable partial"])
        await inference.setFinalOutput("")
        let capture = VoiceInputAudioCaptureFake()
        capture.setSuspendsDrain(true)
        let updates = VoiceInputUpdateRecorder()
        let service = makeVoiceInputService(inference: inference, capture: capture)
        try await prepareAdmittedVoiceInputService(service)
        let session = try await service.beginRecognition(
            attempt: VoiceInputRecognitionAttempt(),
            onUpdate: updates.append
        )
        await capture.emit(.audio(makeVoiceInputPCMTransfer()))

        let stopTask = Task { await service.stopRecognition(session) }
        for _ in 0..<500 where !capture.hasPendingDrain {
            await Task.yield()
        }
        XCTAssertTrue(capture.hasPendingDrain)

        await capture.emit(.failed(.captureQueueOverflow))
        capture.resumePendingDrain()
        let result = await stopTask.value

        XCTAssertEqual(result.transcript, "usable partial")
        XCTAssertEqual(result.termination, .captureFailure)
        XCTAssertEqual(result.error, .captureQueueOverflow)
        XCTAssertTrue(updates.updates.contains(.captureFailed(session: session, error: .captureQueueOverflow)))
    }
}
