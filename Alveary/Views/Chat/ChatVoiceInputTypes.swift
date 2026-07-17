import Foundation

enum ChatVoiceInputActivationSource: Hashable, Sendable {
    case mouse
    case keyboard
}

enum ChatVoiceInputPreparationActivation: Equatable, Sendable {
    case physical(ChatVoiceInputActivationSource)
    case accessibility
}

struct ChatVoiceInputPendingActivation: Equatable, Sendable {
    let activation: ChatVoiceInputPreparationActivation
    let editorDraftIdentity: String?
    let editorDraftGeneration: UInt64
    let composerContext: ChatVoiceInputComposerContext?
}

enum ChatVoiceInputPhase: Equatable, Sendable {
    case unavailable
    case idle
    case preparing(message: String, fraction: Double?)
    case ready
    case starting
    case recording
    case finalizing
    case cancelling
    case cleanup

    var locksDraftMutations: Bool {
        switch self {
        case .recording, .finalizing, .cancelling:
            true
        case .unavailable, .idle, .preparing, .ready, .starting, .cleanup:
            false
        }
    }

    var showsSpinner: Bool {
        switch self {
        case .preparing, .starting, .finalizing, .cancelling, .cleanup:
            true
        case .unavailable, .idle, .ready, .recording:
            false
        }
    }
}

enum ChatVoiceInputModelModalRecovery: Equatable, Sendable {
    case microphoneSettings
}

enum ChatVoiceInputModelModalState: Equatable, Sendable {
    case preparing(VoiceInputPreparationProgress)
    case cancelling
    case ready
    case failed(message: String, recovery: ChatVoiceInputModelModalRecovery?)
}

struct ChatVoiceInputNotice: Equatable, Sendable {
    enum Severity: Equatable, Sendable {
        case info
        case warning
        case error
    }

    enum Recovery: Equatable, Sendable {
        case microphoneSettings
    }

    let message: String
    let severity: Severity
    let recovery: Recovery?
}

enum ChatVoiceInputDraftFinishOutcome: Equatable {
    case committed
    case restored
    case invalidated
    case noTransaction
}

struct ChatVoiceInputComposerContext: Equatable, Sendable {
    let draftIdentity: String
    let inputDraftRevision: Int
    let attachmentIDs: [String]
    let workingDirectory: String?
}

protocol ChatVoiceInputClock: Sendable {
    func now() -> Duration
    func sleep(for duration: Duration) async throws
}

struct ContinuousChatVoiceInputClock: ChatVoiceInputClock {
    private let clock = ContinuousClock()
    private let origin: ContinuousClock.Instant

    init() {
        origin = clock.now
    }

    func now() -> Duration {
        origin.duration(to: clock.now)
    }

    func sleep(for duration: Duration) async throws {
        try await clock.sleep(for: duration)
    }
}

final class ChatVoiceInputCallbackDelivery: @unchecked Sendable {
    private enum Event {
        case preparation(VoiceInputPreparationProgress, generation: UInt64)
        case recognition(VoiceInputRecognitionUpdate, generation: UInt64)
    }

    private let lock = NSLock()
    private weak var coordinator: ChatVoiceInputCoordinator?
    private var events: [Event] = []
    private var drainIsScheduled = false

    init(coordinator: ChatVoiceInputCoordinator) {
        self.coordinator = coordinator
    }

    func deliverPreparation(_ progress: VoiceInputPreparationProgress, generation: UInt64) {
        enqueue(.preparation(progress, generation: generation))
    }

    func deliverRecognition(_ update: VoiceInputRecognitionUpdate, generation: UInt64) {
        enqueue(.recognition(update, generation: generation))
    }

    private func enqueue(_ event: Event) {
        let shouldSchedule = lock.withLock { () -> Bool in
            events.append(event)
            guard !drainIsScheduled else { return false }
            drainIsScheduled = true
            return true
        }
        guard shouldSchedule else { return }
        Task { @MainActor [self] in
            drain()
        }
    }

    @MainActor
    private func drain() {
        while let event = nextEvent() {
            switch event {
            case .preparation(let progress, let generation):
                coordinator?.receivePreparationProgress(progress, generation: generation)
            case .recognition(let update, let generation):
                coordinator?.receiveRecognitionUpdate(update, generation: generation)
            }
        }
    }

    private func nextEvent() -> Event? {
        lock.withLock {
            guard !events.isEmpty else {
                drainIsScheduled = false
                return nil
            }
            return events.removeFirst()
        }
    }
}
