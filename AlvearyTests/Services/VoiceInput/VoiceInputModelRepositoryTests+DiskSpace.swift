@testable import Alveary
import CryptoKit
import Foundation
import XCTest

extension VoiceInputModelRepositoryTests {
    func testDiskPreflightCreditsPinnedPartBytesWithoutMutableValidator() throws {
        let artifact = try makePartialArtifact(size: 1_000, partialSize: 400)
        let partialURL = artifact.repository
            .appendingPathComponent(artifact.model.path)
            .appendingPathExtension("part")
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: temporaryMargin + 600)
        )

        XCTAssertNoThrow(try preflight.validate(
            artifacts: [artifact.model],
            repositoryDirectory: artifact.repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: partialURL.path))
    }

    func testDiskPreflightCreditsCompletePartOnlyAfterDigestValidation() throws {
        let valid = try makePartialArtifact(size: 1_000, partialSize: 1_000)
        let validPart = valid.repository
            .appendingPathComponent(valid.model.path)
            .appendingPathExtension("part")
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: temporaryMargin)
        )
        XCTAssertNoThrow(try preflight.validate(
            artifacts: [valid.model],
            repositoryDirectory: valid.repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: validPart.path))

        let invalid = try makePartialArtifact(size: 1_000, partialSize: 1_000)
        let invalidPart = invalid.repository
            .appendingPathComponent(invalid.model.path)
            .appendingPathExtension("part")
        try Data(repeating: 1, count: 1_000).write(to: invalidPart)
        try assertFullArtifactRequired(invalid)
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidPart.path))
    }

    func testDiskPreflightDoesNotCreditOversizedPart() throws {
        let artifact = try makePartialArtifact(size: 1_000, partialSize: 1_200)
        let partialURL = artifact.repository
            .appendingPathComponent(artifact.model.path)
            .appendingPathExtension("part")
        try assertFullArtifactRequired(artifact)
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    func testDiskPreflightCreditsCompletedArtifactOnlyAfterDigestValidation() throws {
        let valid = try makeCompletedArtifact(data: Data("valid".utf8), expectedData: Data("valid".utf8))
        let invalid = try makeCompletedArtifact(data: Data("wrong".utf8), expectedData: Data("valid".utf8))
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: temporaryMargin)
        )

        XCTAssertNoThrow(try preflight.validate(
            artifacts: [valid.model],
            repositoryDirectory: valid.repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: valid.repository.appendingPathComponent(valid.model.path).path
        ))
        XCTAssertThrowsError(try preflight.validate(
            artifacts: [invalid.model],
            repositoryDirectory: invalid.repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: invalid.repository.appendingPathComponent(invalid.model.path).path
        ))
    }

    func testDiskPreflightRemovesStalePartBesideValidCompletedArtifactBeforeCapacityCheck() throws {
        let artifact = try makeCompletedArtifact(
            data: Data(repeating: 0, count: 1_000),
            expectedData: Data(repeating: 0, count: 1_000)
        )
        let partialURL = artifact.repository
            .appendingPathComponent(artifact.model.path)
            .appendingPathExtension("part")
        try Data(repeating: 1, count: 800).write(to: partialURL)
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: ReclaimingVoiceInputDiskSpaceProvider(
                reclaimedFile: partialURL,
                capacityBeforeReclamation: temporaryMargin - 1,
                reclaimedBytes: 1
            )
        )

        XCTAssertNoThrow(try preflight.validate(
            artifacts: [artifact.model],
            repositoryDirectory: artifact.repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    func testDiskPreflightUsesCapacityReclaimedFromInvalidCompletedArtifact() throws {
        let artifact = try makeCompletedArtifact(
            data: Data(repeating: 1, count: 1_000),
            expectedData: Data(repeating: 0, count: 1_000)
        )
        let invalidURL = artifact.repository.appendingPathComponent(artifact.model.path)
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: ReclaimingVoiceInputDiskSpaceProvider(
                reclaimedFile: invalidURL,
                capacityBeforeReclamation: temporaryMargin,
                reclaimedBytes: artifact.model.size
            )
        )

        XCTAssertNoThrow(try preflight.validate(
            artifacts: [artifact.model],
            repositoryDirectory: artifact.repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
    }

    func testDiskPreflightPurgesOversizedCompletedArtifact() throws {
        let artifact = try makeCompletedArtifact(
            data: Data(repeating: 1, count: 1_200),
            expectedData: Data(repeating: 0, count: 1_000)
        )
        let invalidURL = artifact.repository.appendingPathComponent(artifact.model.path)

        try assertFullArtifactRequired(artifact)

        XCTAssertFalse(FileManager.default.fileExists(atPath: invalidURL.path))
    }

    func testDiskPreflightDoesNotCreditCompletedArtifactSymlink() throws {
        let repository = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let expectedData = Data(repeating: 1, count: 1_000)
        let model = testArtifact(path: "model.bin", data: expectedData)
        let externalTarget = temporaryDirectory.appendingPathComponent("external-final-\(UUID().uuidString)")
        try expectedData.write(to: externalTarget)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let artifactURL = repository.appendingPathComponent(model.path)
        try FileManager.default.createSymbolicLink(
            at: artifactURL,
            withDestinationURL: externalTarget
        )

        try assertFullArtifactRequired(PartialArtifactFixture(model: model, repository: repository))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalTarget.path))
    }

    func testDiskPreflightDoesNotCreditPartialArtifactSymlink() throws {
        let repository = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let expectedData = Data(repeating: 1, count: 1_000)
        let model = testArtifact(path: "model.bin", data: expectedData)
        let externalTarget = temporaryDirectory.appendingPathComponent("external-partial-\(UUID().uuidString)")
        try Data(repeating: 1, count: 400).write(to: externalTarget)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        let partialURL = repository.appendingPathComponent(model.path).appendingPathExtension("part")
        try FileManager.default.createSymbolicLink(
            at: partialURL,
            withDestinationURL: externalTarget
        )

        try assertFullArtifactRequired(PartialArtifactFixture(model: model, repository: repository))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalTarget.path))
    }

    func testDiskPreflightPurgesNonRegularArtifactEntriesBeforeCapacityCheck() throws {
        let repository = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let expectedData = Data(repeating: 0, count: 1_000)
        let model = testArtifact(path: "model.bin", data: expectedData)
        let artifactURL = repository.appendingPathComponent(model.path, isDirectory: true)
        let partialURL = repository.appendingPathComponent(model.path).appendingPathExtension("part")
        try FileManager.default.createDirectory(at: artifactURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 400).write(to: artifactURL.appendingPathComponent("junk"))
        try FileManager.default.createDirectory(at: partialURL, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 400).write(to: partialURL.appendingPathComponent("junk"))
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: ReclaimingEntriesDiskSpaceProvider(
                reclaimedEntries: [artifactURL, partialURL],
                capacityBeforeReclamation: temporaryMargin,
                reclaimedBytes: model.size
            )
        )

        XCTAssertNoThrow(try preflight.validate(
            artifacts: [model],
            repositoryDirectory: repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: artifactURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: partialURL.path))
    }

    func testDiskPreflightDoesNotFollowRepositorySymlink() throws {
        let repository = temporaryDirectory.appendingPathComponent("staging-repository", isDirectory: true)
        let external = temporaryDirectory.appendingPathComponent("external-repository", isDirectory: true)
        let externalArtifact = external.appendingPathComponent("model.bin")
        let externalData = Data(repeating: 1, count: 1_000)
        let model = testArtifact(path: "model.bin", data: Data(repeating: 0, count: 1_000))
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try externalData.write(to: externalArtifact)
        try FileManager.default.createSymbolicLink(at: repository, withDestinationURL: external)
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: temporaryMargin + model.size)
        )

        XCTAssertNoThrow(try preflight.validate(
            artifacts: [model],
            repositoryDirectory: repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: repository.path))
        XCTAssertEqual(try Data(contentsOf: externalArtifact), externalData)
    }

    func testDiskPreflightDoesNotFollowArtifactParentSymlink() throws {
        let repository = temporaryDirectory.appendingPathComponent("nested-repository", isDirectory: true)
        let external = temporaryDirectory.appendingPathComponent("external-parent", isDirectory: true)
        let externalArtifact = external.appendingPathComponent("model.bin")
        let externalData = Data(repeating: 1, count: 1_000)
        let model = testArtifact(path: "weights/model.bin", data: Data(repeating: 0, count: 1_000))
        let linkedParent = repository.appendingPathComponent("weights", isDirectory: true)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        try externalData.write(to: externalArtifact)
        try FileManager.default.createSymbolicLink(at: linkedParent, withDestinationURL: external)
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: temporaryMargin + model.size)
        )

        XCTAssertNoThrow(try preflight.validate(
            artifacts: [model],
            repositoryDirectory: repository,
            modelsDirectory: temporaryDirectory
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: linkedParent.path))
        XCTAssertEqual(try Data(contentsOf: externalArtifact), externalData)
    }

    func testDiskPreflightRejectsArtifactSizeOverflowWithoutTrapping() throws {
        let first = VoiceInputModelArtifact(
            path: "first.bin",
            size: .max,
            digestType: .sha256,
            digest: String(repeating: "0", count: 64)
        )
        let second = VoiceInputModelArtifact(
            path: "second.bin",
            size: 1,
            digestType: .sha256,
            digest: String(repeating: "0", count: 64)
        )

        try assertInvalidArtifactSizes([first, second])
    }

    func testDiskPreflightRejectsTemporaryMarginOverflowWithoutTrapping() throws {
        let artifact = VoiceInputModelArtifact(
            path: "model.bin",
            size: .max,
            digestType: .sha256,
            digest: String(repeating: "0", count: 64)
        )

        try assertInvalidArtifactSizes([artifact])
    }

    private var temporaryMargin: Int64 {
        512 * 1_024 * 1_024
    }

    private func makePartialArtifact(size: Int, partialSize: Int) throws -> PartialArtifactFixture {
        let repository = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let expectedData = Data(repeating: 0, count: size)
        let model = testArtifact(path: "model.bin", data: expectedData)
        let partialURL = repository.appendingPathComponent(model.path).appendingPathExtension("part")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try Data(repeating: 0, count: partialSize).write(to: partialURL)
        return PartialArtifactFixture(model: model, repository: repository)
    }

    private func makeCompletedArtifact(data: Data, expectedData: Data) throws -> PartialArtifactFixture {
        let repository = temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let model = testArtifact(path: "model.bin", data: expectedData)
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try data.write(to: repository.appendingPathComponent(model.path))
        return PartialArtifactFixture(model: model, repository: repository)
    }

    private func testArtifact(path: String, data: Data) -> VoiceInputModelArtifact {
        VoiceInputModelArtifact(
            path: path,
            size: Int64(data.count),
            digestType: .sha256,
            digest: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private func assertFullArtifactRequired(
        _ artifact: PartialArtifactFixture,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: temporaryMargin + 600)
        )
        XCTAssertThrowsError(try preflight.validate(
            artifacts: [artifact.model],
            repositoryDirectory: artifact.repository,
            modelsDirectory: temporaryDirectory
        ), file: file, line: line)
    }

    private func assertInvalidArtifactSizes(
        _ artifacts: [VoiceInputModelArtifact],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        let preflight = VoiceInputModelDiskSpacePreflight(
            fileManager: .default,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )
        XCTAssertThrowsError(try preflight.validate(
            artifacts: artifacts,
            repositoryDirectory: temporaryDirectory,
            modelsDirectory: temporaryDirectory
        ), file: file, line: line) { error in
            guard let serviceError = error as? VoiceInputServiceError,
                  case .modelCache = serviceError else {
                return XCTFail("Unexpected error: \(error)", file: file, line: line)
            }
        }
    }
}

private struct PartialArtifactFixture {
    let model: VoiceInputModelArtifact
    let repository: URL
}

private struct ReclaimingVoiceInputDiskSpaceProvider: VoiceInputDiskSpaceProviding {
    let reclaimedFile: URL
    let capacityBeforeReclamation: Int64
    let reclaimedBytes: Int64

    func availableCapacity(at directory: URL) throws -> Int64? {
        if FileManager.default.fileExists(atPath: reclaimedFile.path) {
            return capacityBeforeReclamation
        }
        return capacityBeforeReclamation + reclaimedBytes
    }
}

private struct ReclaimingEntriesDiskSpaceProvider: VoiceInputDiskSpaceProviding {
    let reclaimedEntries: [URL]
    let capacityBeforeReclamation: Int64
    let reclaimedBytes: Int64

    func availableCapacity(at directory: URL) throws -> Int64? {
        let allEntriesWereRemoved = reclaimedEntries.allSatisfy {
            !FileManager.default.fileExists(atPath: $0.path)
        }
        return capacityBeforeReclamation + (allEntriesWereRemoved ? reclaimedBytes : 0)
    }
}
