@testable import Alveary
import Foundation
import XCTest

final class VoiceInputModelDescriptorTests: XCTestCase {
    func testBundledDescriptorHasExactInitialPinnedInventory() throws {
        let resolved = try BundledVoiceInputModelDescriptorProvider().loadDescriptor()
        let descriptor = resolved.descriptor

        XCTAssertEqual(descriptor.formatVersion, 1)
        XCTAssertEqual(descriptor.repository, "FluidInference/parakeet-unified-en-0.6b-coreml")
        XCTAssertEqual(descriptor.revision, "4252711f6f060f9a2f91e5f081a806d7f45eebd8")
        XCTAssertEqual(descriptor.artifacts.count, 14)
        XCTAssertEqual(descriptor.totalSize, 608_329_613)
        XCTAssertEqual(resolved.sha256, "b3c4ee2702470a71dbb1d5b044ed50f5cfcd6519225cb47f340377bc6ee5c75f")
        XCTAssertEqual(descriptor.artifacts.map(\.path), descriptor.artifacts.map(\.path).sorted())
        XCTAssertTrue(descriptor.artifacts.contains { $0.digestType == .sha256 })
        XCTAssertTrue(descriptor.artifacts.contains { $0.digestType == .gitBlobSHA1 })
        XCTAssertEqual(descriptor.configuration.encoderPrecision, "int8")
        XCTAssertEqual(descriptor.configuration.leftFrames, 70)
        XCTAssertEqual(descriptor.configuration.chunkFrames, 2)
        XCTAssertEqual(descriptor.configuration.rightFrames, 2)
    }

    func testDescriptorRejectsMalformedIdentityInventoryAndDigests() throws {
        let descriptor = try BundledVoiceInputModelDescriptorProvider().loadDescriptor().descriptor
        let firstArtifact = try XCTUnwrap(descriptor.artifacts.first)

        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(descriptor.replacing(formatVersion: 2)))
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(descriptor.replacing(repository: "other/repository")))
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(descriptor.replacing(revision: "main")))
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(
            descriptor.replacing(artifacts: Array(descriptor.artifacts.dropLast()))
        ))
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(
            descriptor.replacing(artifacts: [firstArtifact] + descriptor.artifacts)
        ))
        let invalidDigest = VoiceInputModelArtifact(
            path: firstArtifact.path,
            size: firstArtifact.size,
            digestType: firstArtifact.digestType,
            digest: "not-a-digest"
        )
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(
            descriptor.replacingFirstArtifact(with: invalidDigest)
        ))
        let unsafePath = VoiceInputModelArtifact(
            path: "../metadata.json",
            size: firstArtifact.size,
            digestType: firstArtifact.digestType,
            digest: firstArtifact.digest
        )
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(
            descriptor.replacingFirstArtifact(with: unsafePath)
        ))
    }

    func testDescriptorPathValidationRejectsTraversalAndAmbiguousPaths() {
        for path in ["", "/absolute", "../model", "dir/../model", "dir//model", "dir\\model", "./model"] {
            XCTAssertFalse(VoiceInputModelDescriptorLoader.isSafeRelativePath(path), path)
        }
        XCTAssertTrue(VoiceInputModelDescriptorLoader.isSafeRelativePath("model.mlmodelc/weights/weight.bin"))
    }

    func testDescriptorDecoderRejectsUnknownDigestType() throws {
        let resolved = try BundledVoiceInputModelDescriptorProvider().loadDescriptor()
        var json = try XCTUnwrap(String(data: JSONEncoder().encode(resolved.descriptor), encoding: .utf8))
        json = json.replacingOccurrences(of: "sha256", with: "md5", options: [], range: json.range(of: "sha256"))

        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.load(data: Data(json.utf8)))
    }

    func testDescriptorRejectsArtifactSizeAggregateAndTemporaryMarginOverflow() throws {
        let descriptor = try BundledVoiceInputModelDescriptorProvider().loadDescriptor().descriptor
        let firstArtifact = try XCTUnwrap(descriptor.artifacts.first)
        let overflowingArtifact = VoiceInputModelArtifact(
            path: firstArtifact.path,
            size: .max,
            digestType: firstArtifact.digestType,
            digest: firstArtifact.digest
        )
        let aggregateOverflow = descriptor.replacingFirstArtifact(with: overflowingArtifact)

        XCTAssertNil(aggregateOverflow.totalSize)
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(aggregateOverflow))

        let remainingArtifacts = Array(descriptor.artifacts.dropFirst())
        let remainingSize = try XCTUnwrap(VoiceInputModelSizePolicy.checkedArtifactTotal(remainingArtifacts))
        let marginOverflowTotal = Int64.max - VoiceInputModelSizePolicy.temporaryFileMargin + 1
        let marginOverflowArtifact = VoiceInputModelArtifact(
            path: firstArtifact.path,
            size: marginOverflowTotal - remainingSize,
            digestType: firstArtifact.digestType,
            digest: firstArtifact.digest
        )
        let marginOverflow = descriptor.replacingFirstArtifact(with: marginOverflowArtifact)

        XCTAssertEqual(marginOverflow.totalSize, marginOverflowTotal)
        XCTAssertThrowsError(try VoiceInputModelDescriptorLoader.validate(marginOverflow))
    }
}

private extension VoiceInputPinnedModelDescriptor {
    func replacing(
        formatVersion: Int? = nil,
        repository: String? = nil,
        revision: String? = nil,
        artifacts: [VoiceInputModelArtifact]? = nil
    ) -> VoiceInputPinnedModelDescriptor {
        VoiceInputPinnedModelDescriptor(
            formatVersion: formatVersion ?? self.formatVersion,
            repository: repository ?? self.repository,
            revision: revision ?? self.revision,
            configuration: configuration,
            artifacts: artifacts ?? self.artifacts
        )
    }

    func replacingFirstArtifact(with artifact: VoiceInputModelArtifact) -> VoiceInputPinnedModelDescriptor {
        replacing(artifacts: [artifact] + artifacts.dropFirst())
    }
}
