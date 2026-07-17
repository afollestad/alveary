import CryptoKit
import Foundation

protocol VoiceInputModelDescriptorProviding: Sendable {
    func loadDescriptor() throws -> VoiceInputResolvedModelDescriptor
}

struct BundledVoiceInputModelDescriptorProvider: VoiceInputModelDescriptorProviding {
    func loadDescriptor() throws -> VoiceInputResolvedModelDescriptor {
        guard let url = Bundle.main.url(forResource: "VoiceInputModelDescriptor", withExtension: "json") else {
            throw VoiceInputServiceError.modelCache("The bundled voice model descriptor is missing.")
        }
        return try VoiceInputModelDescriptorLoader.load(from: url)
    }
}

enum VoiceInputModelDescriptorLoader {
    static func load(from url: URL) throws -> VoiceInputResolvedModelDescriptor {
        try load(data: Data(contentsOf: url))
    }

    static func load(data: Data) throws -> VoiceInputResolvedModelDescriptor {
        let descriptor: VoiceInputPinnedModelDescriptor
        do {
            descriptor = try JSONDecoder().decode(VoiceInputPinnedModelDescriptor.self, from: data)
        } catch {
            throw VoiceInputServiceError.modelCache("The bundled voice model descriptor could not be decoded.")
        }
        try validate(descriptor)
        return VoiceInputResolvedModelDescriptor(
            descriptor: descriptor,
            sha256: Self.sha256(data)
        )
    }

    static func validate(_ descriptor: VoiceInputPinnedModelDescriptor) throws {
        guard descriptor.formatVersion == VoiceInputPinnedModelDescriptor.currentFormatVersion else {
            throw invalid("The voice model descriptor format is unsupported.")
        }
        guard descriptor.repository == VoiceInputPinnedModelDescriptor.expectedRepository else {
            throw invalid("The voice model descriptor names an unexpected repository.")
        }
        guard descriptor.revision.count == 40, descriptor.revision.allSatisfy(\.isLowercaseHexDigit) else {
            throw invalid("The voice model descriptor revision is not an exact commit.")
        }
        guard descriptor.configuration == expectedConfiguration else {
            throw invalid("The voice model descriptor has an unsupported ASR configuration.")
        }
        guard descriptor.artifacts.count == VoiceInputPinnedModelDescriptor.expectedArtifactCount else {
            throw invalid("The voice model descriptor does not contain exactly 14 artifacts.")
        }
        let paths = descriptor.artifacts.map(\.path)
        guard paths == paths.sorted() else {
            throw invalid("The voice model descriptor artifacts are not sorted.")
        }
        guard Set(paths).count == paths.count else {
            throw invalid("The voice model descriptor contains duplicate artifact paths.")
        }
        guard Set(paths) == expectedArtifactPaths else {
            throw invalid("The voice model descriptor contains missing or unexpected artifacts.")
        }
        for artifact in descriptor.artifacts {
            try validate(artifact)
        }
        guard let totalSize = descriptor.totalSize,
              VoiceInputModelSizePolicy.checkedRequiredBytes(for: totalSize) != nil else {
            throw invalid("The voice model descriptor artifact sizes are too large.")
        }
    }

    static func isSafeRelativePath(_ path: String) -> Bool {
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              !path.contains("\0") else {
            return false
        }
        let components = path.split(separator: "/", omittingEmptySubsequences: false)
        return !components.isEmpty && components.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func validate(_ artifact: VoiceInputModelArtifact) throws {
        guard isSafeRelativePath(artifact.path) else {
            throw invalid("The voice model descriptor contains an unsafe artifact path.")
        }
        guard artifact.size > 0 else {
            throw invalid("The voice model descriptor contains an invalid artifact size.")
        }
        let expectedLength = artifact.digestType == .sha256 ? 64 : 40
        guard artifact.digest.count == expectedLength,
              artifact.digest.allSatisfy(\.isLowercaseHexDigit) else {
            throw invalid("The voice model descriptor contains an invalid artifact digest.")
        }
    }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func invalid(_ message: String) -> VoiceInputServiceError {
        .modelCache(message)
    }

    private static let expectedConfiguration = VoiceInputModelASRConfiguration(
        encoderPrecision: "int8",
        leftFrames: 70,
        chunkFrames: 2,
        rightFrames: 2,
        encoder: "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc"
    )

    private static let expectedArtifactPaths: Set<String> = [
        "metadata.json",
        "parakeet_unified_decoder.mlmodelc/analytics/coremldata.bin",
        "parakeet_unified_decoder.mlmodelc/coremldata.bin",
        "parakeet_unified_decoder.mlmodelc/model.mil",
        "parakeet_unified_decoder.mlmodelc/weights/weight.bin",
        "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc/analytics/coremldata.bin",
        "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc/coremldata.bin",
        "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc/model.mil",
        "parakeet_unified_encoder_streaming_70_2_2_int8.mlmodelc/weights/weight.bin",
        "parakeet_unified_joint_decision_single_step.mlmodelc/analytics/coremldata.bin",
        "parakeet_unified_joint_decision_single_step.mlmodelc/coremldata.bin",
        "parakeet_unified_joint_decision_single_step.mlmodelc/model.mil",
        "parakeet_unified_joint_decision_single_step.mlmodelc/weights/weight.bin",
        "vocab.json"
    ]
}

private extension Character {
    var isLowercaseHexDigit: Bool {
        ("0"..."9").contains(self) || ("a"..."f").contains(self)
    }
}
