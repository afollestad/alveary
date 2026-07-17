@testable import Alveary
import CryptoKit
import Foundation

struct StaticVoiceInputModelDescriptorProvider: VoiceInputModelDescriptorProviding {
    let resolvedDescriptor: VoiceInputResolvedModelDescriptor

    func loadDescriptor() throws -> VoiceInputResolvedModelDescriptor {
        resolvedDescriptor
    }
}

actor VoiceInputModelDownloaderFake: VoiceInputModelDownloading {
    enum Failure: Equatable, Sendable {
        case cancellation
        case diskFull
        case network
    }

    private let artifactData: [String: Data]
    private let failure: Failure?
    private let progressFractions: [Double]
    private(set) var downloadCount = 0
    private(set) var observedExistingFiles: [String] = []

    init(
        artifactData: [String: Data],
        failure: Failure? = nil,
        progressFractions: [Double] = [1]
    ) {
        self.artifactData = artifactData
        self.failure = failure
        self.progressFractions = progressFractions
    }

    func download(
        descriptor: VoiceInputPinnedModelDescriptor,
        to repositoryDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        downloadCount += 1
        observedExistingFiles = descriptor.artifacts.filter {
            FileManager.default.fileExists(
                atPath: repositoryDirectory.appendingPathComponent($0.path).path
            )
        }.map(\.path)
        try FileManager.default.createDirectory(at: repositoryDirectory, withIntermediateDirectories: true)
        if failure == .cancellation, let first = descriptor.artifacts.first {
            let partURL = repositoryDirectory.appendingPathComponent(first.path).appendingPathExtension("part")
            try FileManager.default.createDirectory(
                at: partURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try Data((artifactData[first.path] ?? Data()).prefix(1)).write(to: partURL)
            throw CancellationError()
        }
        if failure == .diskFull {
            throw POSIXError(.ENOSPC)
        }
        if failure == .network {
            throw URLError(.networkConnectionLost)
        }

        for artifact in descriptor.artifacts {
            let url = repositoryDirectory.appendingPathComponent(artifact.path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try artifactData[artifact.path, default: Data()].write(to: url)
        }
        progressFractions.forEach(progress)
    }
}

struct FixedVoiceInputDiskSpaceProvider: VoiceInputDiskSpaceProviding {
    let capacity: Int64?

    func availableCapacity(at directory: URL) throws -> Int64? {
        capacity
    }
}

struct FailingVoiceInputDiskSpaceProvider: VoiceInputDiskSpaceProviding {
    let error: POSIXError

    func availableCapacity(at directory: URL) throws -> Int64? {
        throw error
    }
}

struct VoiceInputTestModelDescriptor {
    let resolved: VoiceInputResolvedModelDescriptor
    let dataByPath: [String: Data]
}

func makeVoiceInputTestModelDescriptor(
    revision: String = String(repeating: "a", count: 40),
    dataByPath: [String: Data] = ["model.bin": Data("model".utf8)],
    descriptorSHA256: String = String(repeating: "d", count: 64)
) -> VoiceInputTestModelDescriptor {
    let artifacts = dataByPath.keys.sorted().map { path in
        let data = dataByPath[path, default: Data()]
        return VoiceInputModelArtifact(
            path: path,
            size: Int64(data.count),
            digestType: .sha256,
            digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }
    let descriptor = VoiceInputPinnedModelDescriptor(
        formatVersion: VoiceInputPinnedModelDescriptor.currentFormatVersion,
        repository: VoiceInputPinnedModelDescriptor.expectedRepository,
        revision: revision,
        configuration: VoiceInputModelASRConfiguration(
            encoderPrecision: "int8",
            leftFrames: 70,
            chunkFrames: 2,
            rightFrames: 2,
            encoder: "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc"
        ),
        artifacts: artifacts
    )
    return VoiceInputTestModelDescriptor(
        resolved: VoiceInputResolvedModelDescriptor(
            descriptor: descriptor,
            sha256: descriptorSHA256
        ),
        dataByPath: dataByPath
    )
}
