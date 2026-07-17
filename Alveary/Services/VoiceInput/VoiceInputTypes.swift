import Foundation

final class VoiceInputRecognitionAttempt: @unchecked Sendable, Hashable {
    let id: UUID

    private let lock = NSLock()
    private var cancellationHandler: (@Sendable () -> Void)?
    private var isCancelled = false
    private var isFinished = false

    init(id: UUID = UUID()) {
        self.id = id
    }

    static func == (lhs: VoiceInputRecognitionAttempt, rhs: VoiceInputRecognitionAttempt) -> Bool {
        lhs === rhs
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(ObjectIdentifier(self))
    }

    func installCancellationHandler(_ handler: @escaping @Sendable () -> Void) -> Bool {
        lock.withLock {
            guard !isCancelled, !isFinished, cancellationHandler == nil else { return false }
            cancellationHandler = handler
            return true
        }
    }

    func cancelSynchronously() {
        let handler = lock.withLock { () -> (@Sendable () -> Void)? in
            guard !isCancelled, !isFinished else { return nil }
            isCancelled = true
            defer { cancellationHandler = nil }
            return cancellationHandler
        }
        handler?()
    }

    func finish() {
        lock.withLock {
            guard !isFinished else { return }
            isFinished = true
            cancellationHandler = nil
        }
    }

    var cancelled: Bool {
        lock.withLock { isCancelled }
    }
}

struct VoiceInputRecognitionSession: Hashable, Sendable {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

enum VoiceInputPermissionStatus: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum VoiceInputPreparationProgress: Equatable, Sendable {
    case checkingPermission
    case checkingModel
    case downloading(kind: VoiceInputModelPreparationKind, fraction: Double?)
    case loadingModel
    case ready
}

enum VoiceInputModelPreparationMode: Equatable, Sendable {
    case normal
    case repair
}

enum VoiceInputModelPreparationKind: Equatable, Sendable {
    case installation
    case update
    case repair
}

enum VoiceInputPreparationSource: Equatable, Sendable {
    case inMemory
    case validatedCache
    case downloaded(VoiceInputModelPreparationKind)
}

struct VoiceInputPreparationResult: Equatable, Sendable {
    let source: VoiceInputPreparationSource
    let requestedMicrophonePermission: Bool
}

enum VoiceInputPreparationAdmission: Equatable, Sendable {
    case ready
    case initiated
    case busy
}

enum VoiceInputRecognitionUpdate: Equatable, Sendable {
    case partial(session: VoiceInputRecognitionSession, text: String)
    case captureFailed(session: VoiceInputRecognitionSession, error: VoiceInputServiceError)
    case stopped(session: VoiceInputRecognitionSession, result: VoiceInputRecognitionResult)
}

struct VoiceInputRecognitionResult: Equatable, Sendable {
    enum Termination: Equatable, Sendable {
        case committed
        case cancelled
        case captureFailure
        case inferenceFailure
        case shutdown
    }

    let transcript: String?
    let termination: Termination
    let error: VoiceInputServiceError?

    static let cancelled = VoiceInputRecognitionResult(
        transcript: nil,
        termination: .cancelled,
        error: nil
    )
}

enum VoiceInputServiceError: Error, Equatable, Sendable {
    case unsupportedArchitecture
    case permissionNotDetermined
    case permissionDenied
    case permissionRestricted
    case noInputDevice
    case invalidInputFormat
    case alreadyRecording
    case modelPreparationBusy
    case modelCacheBusy
    case recognitionSessionExpired
    case captureQueueOverflow
    case deviceConfigurationChanged
    case systemSleep
    case insufficientDiskSpace(requiredBytes: Int64, availableBytes: Int64)
    case diskFull
    case modelDownload(String)
    case modelCache(String)
    case modelLoad(String)
    case audioCapture(String)
    case inference(String)

    var isPermissionDenial: Bool {
        self == .permissionDenied
    }
}

extension VoiceInputServiceError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .unsupportedArchitecture:
            return "Voice input requires a Mac with Apple silicon."
        case .permissionNotDetermined:
            return "Microphone access must be requested before dictation can start."
        case .permissionDenied:
            return "Microphone access is denied."
        case .permissionRestricted:
            return "Microphone access is restricted on this Mac."
        case .noInputDevice:
            return "No microphone is available."
        case .invalidInputFormat:
            return "The selected microphone reported an invalid audio format."
        case .alreadyRecording:
            return "Another dictation session is already active."
        case .modelPreparationBusy:
            return "Voice model setup is already in progress."
        case .modelCacheBusy:
            return "Stop dictation or wait for voice model preparation to finish before clearing the voice model cache."
        case .recognitionSessionExpired:
            return "This dictation session is no longer active."
        case .captureQueueOverflow:
            return "Voice input could not keep up with the microphone."
        case .deviceConfigurationChanged:
            return "The microphone configuration changed during dictation."
        case .systemSleep:
            return "Dictation stopped because the Mac is going to sleep."
        case .insufficientDiskSpace(let requiredBytes, let availableBytes):
            return "Voice input needs \(requiredBytes) bytes of free space, but only \(availableBytes) bytes are available."
        case .diskFull:
            return "The voice model download stopped because the disk is full."
        case .modelDownload(let message):
            return "Could not download the voice model: \(message)"
        case .modelCache(let message):
            return "The voice model cache is invalid: \(message)"
        case .modelLoad(let message):
            return "Could not load the voice model: \(message)"
        case .audioCapture(let message):
            return "Could not capture microphone audio: \(message)"
        case .inference(let message):
            return "Voice recognition failed: \(message)"
        }
    }
}

enum VoiceInputModelDigestType: String, Codable, Equatable, Sendable {
    case sha256
    case gitBlobSHA1
}

struct VoiceInputModelArtifact: Codable, Equatable, Sendable {
    let path: String
    let size: Int64
    let digestType: VoiceInputModelDigestType
    let digest: String
}

enum VoiceInputModelSizePolicy {
    static let temporaryFileMargin: Int64 = 512 * 1_024 * 1_024

    static func checkedArtifactTotal(_ artifacts: [VoiceInputModelArtifact]) -> Int64? {
        var total: Int64 = 0
        for artifact in artifacts {
            guard artifact.size > 0,
                  let next = checkedAdding(artifact.size, to: total) else {
                return nil
            }
            total = next
        }
        return total
    }

    static func checkedRequiredBytes(for remainingBytes: Int64) -> Int64? {
        guard remainingBytes >= 0 else { return nil }
        return checkedAdding(temporaryFileMargin, to: remainingBytes)
    }

    static func checkedAdding(_ value: Int64, to total: Int64) -> Int64? {
        guard value >= 0 else { return nil }
        let (result, overflow) = total.addingReportingOverflow(value)
        return overflow ? nil : result
    }
}

struct VoiceInputModelASRConfiguration: Codable, Equatable, Sendable {
    let encoderPrecision: String
    let leftFrames: Int
    let chunkFrames: Int
    let rightFrames: Int
    let encoder: String
}

struct VoiceInputPinnedModelDescriptor: Codable, Equatable, Sendable {
    static let currentFormatVersion = 1
    static let expectedRepository = "FluidInference/parakeet-unified-en-0.6b-coreml"
    static let expectedArtifactCount = 14

    let formatVersion: Int
    let repository: String
    let revision: String
    let configuration: VoiceInputModelASRConfiguration
    let artifacts: [VoiceInputModelArtifact]

    var totalSize: Int64? {
        VoiceInputModelSizePolicy.checkedArtifactTotal(artifacts)
    }
}

struct VoiceInputResolvedModelDescriptor: Equatable, Sendable {
    let descriptor: VoiceInputPinnedModelDescriptor
    let sha256: String
}

struct VoiceInputModelManifest: Codable, Equatable, Sendable {
    static let currentSchema = 2
    static let fluidAudioRevision = "19600a485baa4998812e4654b70d2bab8f2c9949"

    let schema: Int
    let fluidAudioRevision: String
    let repository: String
    let modelRevision: String
    let descriptorSHA256: String
    let configuration: VoiceInputModelASRConfiguration
    let artifacts: [VoiceInputModelArtifact]
}

struct VoiceInputPreparedModel: Equatable, Sendable {
    enum Source: Equatable, Sendable {
        case validatedCache
        case downloaded(VoiceInputModelPreparationKind)
    }

    let repositoryDirectory: URL
    let manifest: VoiceInputModelManifest
    let source: Source
}
