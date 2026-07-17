import Foundation
import XCTest

@testable import Alveary

@MainActor
extension DefaultVoiceInputServiceTests {
    func testModelRepairWaitsForInferenceCleanupBeforePurgingValidatedCache() async throws {
        let order = VoiceInputModelRepairOrderRecorder()
        let progress = VoiceInputProgressRecorder()
        let repository = OrderedVoiceInputModelRepositoryFake(order: order)
        let inference = SuspendingCleanupVoiceInputInferenceFake(order: order)
        let service = DefaultVoiceInputService(
            permissionProvider: VoiceInputPermissionFake(status: .authorized),
            modelRepository: repository,
            inferenceEngine: inference,
            audioCaptureFactory: { VoiceInputAudioCaptureFake() },
            suddenTerminationController: SuddenTerminationControllerFake(),
            memoryPressureMonitor: MemoryPressureMonitorFake(),
            architectureCheck: { true }
        )

        let preparation = Task {
            try await prepareAdmittedVoiceInputService(service, progress: progress.append)
        }
        await waitForPendingRepairCleanup(inference)

        XCTAssertEqual(order.events, [.initialPreparation, .loadFailed, .cleanupStarted])
        XCTAssertFalse(order.events.contains(.validatedCachePurged))
        XCTAssertEqual(progress.values, [
            .checkingPermission,
            .loadingModel,
            .downloading(kind: .repair, fraction: nil)
        ])

        await inference.resumeCleanup()
        let result = try await preparation.value

        XCTAssertEqual(order.events, [
            .initialPreparation,
            .loadFailed,
            .cleanupStarted,
            .cleanupCompleted,
            .validatedCachePurged,
            .forcedRedownload,
            .repairLoadSucceeded
        ])
        XCTAssertEqual(result.source, .downloaded(.repair))
        XCTAssertFalse(result.requestedMicrophonePermission)
    }

    private func waitForPendingRepairCleanup(_ inference: SuspendingCleanupVoiceInputInferenceFake) async {
        for _ in 0..<500 {
            if await inference.hasPendingCleanup {
                return
            }
            await Task.yield()
        }
        XCTFail("Expected inference cleanup to suspend before cache purge")
    }
}

private final class VoiceInputModelRepairOrderRecorder: @unchecked Sendable {
    enum Event: Equatable {
        case initialPreparation
        case loadFailed
        case cleanupStarted
        case cleanupCompleted
        case validatedCachePurged
        case forcedRedownload
        case repairLoadSucceeded
    }

    private let lock = NSLock()
    private var storage: [Event] = []

    var events: [Event] {
        lock.withLock { storage }
    }

    func append(_ event: Event) {
        lock.withLock {
            storage.append(event)
        }
    }
}

private actor OrderedVoiceInputModelRepositoryFake: VoiceInputModelRepository {
    private let order: VoiceInputModelRepairOrderRecorder

    init(order: VoiceInputModelRepairOrderRecorder) {
        self.order = order
    }

    func prepareModel(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel {
        order.append(mode == .repair ? .forcedRedownload : .initialPreparation)
        return makeVoiceInputPreparedModel()
    }

    func purgeValidatedModel() async throws {
        order.append(.validatedCachePurged)
    }
}

private actor SuspendingCleanupVoiceInputInferenceFake: VoiceInputInferenceEngine {
    private let order: VoiceInputModelRepairOrderRecorder
    private var cleanupContinuation: CheckedContinuation<Void, Never>?
    private var loadCount = 0

    init(order: VoiceInputModelRepairOrderRecorder) {
        self.order = order
    }

    var hasPendingCleanup: Bool {
        cleanupContinuation != nil
    }

    func loadModels(from directory: URL) async throws {
        loadCount += 1
        if loadCount == 1 {
            order.append(.loadFailed)
            throw VoiceInputServiceError.modelLoad("corrupt")
        }
        order.append(.repairLoadSucceeded)
    }

    func reset() async throws {}

    func process(_ buffer: VoiceInputPCMTransfer) async throws -> String {
        ""
    }

    func finishAndReset() async throws -> VoiceInputInferenceFinalization {
        VoiceInputInferenceFinalization(transcript: "", isReusable: true)
    }

    func cancelAndReset() async -> Bool {
        true
    }

    func cleanup() async {
        order.append(.cleanupStarted)
        await withCheckedContinuation { continuation in
            cleanupContinuation = continuation
        }
        order.append(.cleanupCompleted)
    }

    func resumeCleanup() {
        let continuation = cleanupContinuation
        cleanupContinuation = nil
        continuation?.resume()
    }
}
