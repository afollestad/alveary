@testable import Alveary
import AVFoundation
import XCTest

@MainActor
final class VoiceInputPCMQueueTests: XCTestCase {
    func testCapacityIncludesChunkAlreadyHandedToWorker() throws {
        let queue = VoiceInputPCMQueue(generation: 7, maximumDuration: 2)
        let first = try copiedBuffer(duration: 1.2)
        let second = try copiedBuffer(duration: 1)

        queue.enqueue(first, generation: 7)
        guard case .some(.audio) = queue.next() else {
            return XCTFail("Expected the first audio chunk")
        }
        queue.enqueue(second, generation: 7)

        guard case .some(.failure(.captureQueueOverflow)) = queue.next() else {
            return XCTFail("Expected overflow while the first chunk remains in flight")
        }
    }

    func testCompletingInFlightChunkReleasesCapacity() throws {
        let queue = VoiceInputPCMQueue(generation: 3, maximumDuration: 2)
        let first = try copiedBuffer(duration: 1.2)
        let second = try copiedBuffer(duration: 1)

        queue.enqueue(first, generation: 3)
        guard case .some(.audio) = queue.next() else {
            return XCTFail("Expected the first audio chunk")
        }
        queue.complete(duration: first.duration)
        queue.enqueue(second, generation: 3)

        guard case .some(.audio) = queue.next() else {
            return XCTFail("Expected the second chunk after capacity was released")
        }
    }

    func testStaleGenerationIsIgnored() throws {
        let queue = VoiceInputPCMQueue(generation: 9, maximumDuration: 2)
        queue.enqueue(try copiedBuffer(duration: 0.1), generation: 8)
        XCTAssertNil(queue.next())
    }

    func testCloseDrainsChunkReservedBeforeAdmissionClosed() throws {
        let queue = VoiceInputPCMQueue(generation: 4, maximumDuration: 2)
        let accepted = try copiedBuffer(duration: 0.5)

        XCTAssertTrue(queue.reserve(duration: accepted.duration, generation: 4))
        queue.close()
        XCTAssertNil(queue.next())

        queue.commitReserved(accepted)
        guard case .some(.audio) = queue.next() else {
            return XCTFail("Expected the reserved audio chunk to drain")
        }
        queue.complete(duration: accepted.duration)
        guard case .some(.finished) = queue.next() else {
            return XCTFail("Expected the closed queue to finish after draining")
        }
    }

    func testOverflowWaitsForAcceptedReservationBeforeFailure() throws {
        let queue = VoiceInputPCMQueue(generation: 5, maximumDuration: 2)
        let accepted = try copiedBuffer(duration: 1.5)

        XCTAssertTrue(queue.reserve(duration: accepted.duration, generation: 5))
        XCTAssertFalse(queue.reserve(duration: 1, generation: 5))
        XCTAssertNil(queue.next())

        queue.commitReserved(accepted)
        guard case .some(.audio) = queue.next() else {
            return XCTFail("Expected accepted audio before the overflow failure")
        }
        queue.complete(duration: accepted.duration)
        guard case .some(.failure(.captureQueueOverflow)) = queue.next() else {
            return XCTFail("Expected overflow after accepted audio drained")
        }
    }

    func testDiscardDropsQueuedAudioAndTerminalFailure() throws {
        let queue = VoiceInputPCMQueue(generation: 5, maximumDuration: 2)
        queue.enqueue(try copiedBuffer(duration: 0.5), generation: 5)
        queue.fail(.deviceConfigurationChanged)

        queue.discard()

        guard case .some(.finished) = queue.next() else {
            return XCTFail("Expected discard to finish without queued audio or failure")
        }
    }

    func testDiscardUpgradesClosedQueueBeforeDrainCompletes() throws {
        let queue = VoiceInputPCMQueue(generation: 8, maximumDuration: 2)
        let inFlight = try copiedBuffer(duration: 0.5)
        let queued = try copiedBuffer(duration: 0.5)
        queue.enqueue(inFlight, generation: 8)
        queue.enqueue(queued, generation: 8)
        queue.close()

        guard case .some(.audio) = queue.next() else {
            return XCTFail("Expected an in-flight chunk")
        }
        queue.discard()
        queue.complete(duration: inFlight.duration)

        guard case .some(.finished) = queue.next() else {
            return XCTFail("Expected discard to remove audio queued behind the in-flight chunk")
        }
    }

    func testFailureAfterIntentionalCloseDoesNotReplaceFinishedTerminal() {
        let queue = VoiceInputPCMQueue(generation: 9, maximumDuration: 2)
        queue.close()
        queue.fail(.deviceConfigurationChanged)

        guard case .some(.finished) = queue.next() else {
            return XCTFail("Expected intentional close to ignore a later device failure")
        }
    }

    func testDiscardWaitsForReservedCopyThenDropsIt() throws {
        let queue = VoiceInputPCMQueue(generation: 6, maximumDuration: 2)
        let accepted = try copiedBuffer(duration: 0.5)
        XCTAssertTrue(queue.reserve(duration: accepted.duration, generation: 6))

        queue.discard()
        XCTAssertNil(queue.next())
        queue.commitReserved(accepted)

        guard case .some(.finished) = queue.next() else {
            return XCTFail("Expected the reserved copy to be discarded before finishing")
        }
    }

    func testCopiedPCMDoesNotAliasTapBufferMemory() throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 1)!
        let source = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 16)!
        source.frameLength = 16
        source.floatChannelData?[0][0] = 0.75
        let copied = try VoiceInputCopiedPCM(copying: source)

        source.floatChannelData?[0][0] = -0.25
        let transfer = try copied.makeTransfer()

        XCTAssertEqual(transfer.buffer.floatChannelData?[0][0], 0.75)
    }

    private func copiedBuffer(duration: TimeInterval) throws -> VoiceInputCopiedPCM {
        let sampleRate = 16_000.0
        let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)!
        let frames = AVAudioFrameCount(sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        return try VoiceInputCopiedPCM(copying: buffer)
    }
}
