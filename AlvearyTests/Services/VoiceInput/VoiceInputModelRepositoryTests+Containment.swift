@testable import Alveary
import Darwin
import Foundation
import XCTest

extension VoiceInputModelRepositoryTests {
    func testRemoveUnpinnedModelsDoesNotFollowReplacedModelCacheRootSymlink() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-model-root", isDirectory: true)
        let externalRevision = externalDirectory.appendingPathComponent(
            String(VoiceInputModelManifest.currentSchema),
            isDirectory: true
        ).appendingPathComponent("external-revision", isDirectory: true)
        let sentinel = externalRevision.appendingPathComponent("sentinel.txt")
        let modelsDirectory = temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: externalRevision, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: modelsDirectory, withDestinationURL: externalDirectory)
        let repository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)

        try await repository.removeUnpinnedModels()

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalRevision.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsDirectory.path))
    }

    func testRemoveUnpinnedModelsDoesNotFollowReplacedSchemaDirectorySymlink() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let modelsDirectory = temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
        let schemaDirectory = modelsDirectory.appendingPathComponent(
            String(VoiceInputModelManifest.currentSchema),
            isDirectory: true
        )
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-schema", isDirectory: true)
        let externalRevision = externalDirectory.appendingPathComponent("external-revision", isDirectory: true)
        let sentinel = externalRevision.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalRevision, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: schemaDirectory, withDestinationURL: externalDirectory)
        let repository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)

        try await repository.removeUnpinnedModels()

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalRevision.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: schemaDirectory.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: modelsDirectory.path))
    }

    func testPurgeValidatedModelDoesNotFollowReplacedRevisionDirectorySymlink() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let modelsDirectory = temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
        let revisionDirectory = modelsDirectory
            .appendingPathComponent(String(VoiceInputModelManifest.currentSchema), isDirectory: true)
            .appendingPathComponent(fixture.resolved.descriptor.revision, isDirectory: true)
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-revision", isDirectory: true)
        let externalValidated = externalDirectory.appendingPathComponent("validated", isDirectory: true)
        let sentinel = externalValidated.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(
            at: revisionDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(at: externalValidated, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: revisionDirectory, withDestinationURL: externalDirectory)
        let repository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)

        try await repository.purgeValidatedModel()

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalValidated.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: revisionDirectory.path))
    }

    func testPurgeAllModelsUnlinksReplacedRootSymlinkWithoutTouchingExternalTarget() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-purge-all", isDirectory: true)
        let sentinel = externalDirectory.appendingPathComponent("sentinel.txt")
        let modelsDirectory = temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: modelsDirectory, withDestinationURL: externalDirectory)
        let repository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)

        try await repository.purgeAllModels()

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelsDirectory.path))
    }

    func testPurgeAllModelsRejectsAncestorSymlinkWithoutTouchingExternalTarget() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let cacheOwnershipDirectory = temporaryDirectory.appendingPathComponent("owned-cache", isDirectory: true)
        let voiceInputDirectory = cacheOwnershipDirectory.appendingPathComponent("VoiceInput", isDirectory: true)
        let modelsDirectory = voiceInputDirectory.appendingPathComponent("Models", isDirectory: true)
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-voice-input", isDirectory: true)
        let externalModelsDirectory = externalDirectory.appendingPathComponent("Models", isDirectory: true)
        let sentinel = externalModelsDirectory.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: cacheOwnershipDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalModelsDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: voiceInputDirectory, withDestinationURL: externalDirectory)
        let repository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: cacheOwnershipDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
            downloader: VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath),
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        do {
            try await repository.purgeAllModels()
            XCTFail("Expected unsafe cache path rejection")
        } catch let error as VoiceInputServiceError {
            guard case .modelCache = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalModelsDirectory.path))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: voiceInputDirectory.path)[.type] as? FileAttributeType,
            .typeSymbolicLink
        )
    }

    func testPreparationRejectsAncestorSymlinkWithoutTouchingExternalTarget() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let cacheOwnershipDirectory = temporaryDirectory.appendingPathComponent("owned-preparation-cache", isDirectory: true)
        let voiceInputDirectory = cacheOwnershipDirectory.appendingPathComponent("VoiceInput", isDirectory: true)
        let modelsDirectory = voiceInputDirectory.appendingPathComponent("Models", isDirectory: true)
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-preparation", isDirectory: true)
        let externalModelsDirectory = externalDirectory.appendingPathComponent("Models", isDirectory: true)
        let sentinel = externalModelsDirectory.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: cacheOwnershipDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalModelsDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: voiceInputDirectory, withDestinationURL: externalDirectory)
        let downloader = VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath)
        let repository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: cacheOwnershipDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
            downloader: downloader,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        do {
            _ = try await repository.prepareModel(mode: .normal) { _ in }
            XCTFail("Expected unsafe cache path rejection")
        } catch let error as VoiceInputServiceError {
            guard case .modelCache = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
        let downloadCount = await downloader.downloadCount

        XCTAssertEqual(downloadCount, 0)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertTrue(FileManager.default.fileExists(atPath: externalModelsDirectory.path))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: voiceInputDirectory.path)[.type] as? FileAttributeType,
            .typeSymbolicLink
        )
    }

    func testPreparationRejectsCacheOwnershipDirectorySymlinkWithoutTouchingExternalTarget() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let cacheOwnershipDirectory = temporaryDirectory.appendingPathComponent("owned-cache-link", isDirectory: true)
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-owned-cache", isDirectory: true)
        let externalModelsDirectory = externalDirectory
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let sentinel = externalModelsDirectory.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: externalModelsDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: cacheOwnershipDirectory, withDestinationURL: externalDirectory)
        let modelsDirectory = cacheOwnershipDirectory
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let downloader = VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath)
        let repository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: cacheOwnershipDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
            downloader: downloader,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        do {
            _ = try await repository.prepareModel(mode: .normal) { _ in }
            XCTFail("Expected unsafe cache ownership path rejection")
        } catch let error as VoiceInputServiceError {
            guard case .modelCache = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        let downloadCount = await downloader.downloadCount
        XCTAssertEqual(downloadCount, 0)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: cacheOwnershipDirectory.path)[.type] as? FileAttributeType,
            .typeSymbolicLink
        )
    }

    func testPurgeAllModelsRejectsCacheOwnershipDirectorySymlinkWithoutTouchingExternalTarget() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let cacheOwnershipDirectory = temporaryDirectory.appendingPathComponent("owned-purge-cache-link", isDirectory: true)
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-owned-purge-cache", isDirectory: true)
        let externalModelsDirectory = externalDirectory
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let sentinel = externalModelsDirectory.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: externalModelsDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(at: cacheOwnershipDirectory, withDestinationURL: externalDirectory)
        let modelsDirectory = cacheOwnershipDirectory
            .appendingPathComponent("VoiceInput", isDirectory: true)
            .appendingPathComponent("Models", isDirectory: true)
        let repository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: cacheOwnershipDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
            downloader: VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath),
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        do {
            try await repository.purgeAllModels()
            XCTFail("Expected unsafe cache ownership path rejection")
        } catch let error as VoiceInputServiceError {
            guard case .modelCache = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: cacheOwnershipDirectory.path)[.type] as? FileAttributeType,
            .typeSymbolicLink
        )
    }

    func testPreparationNormalizesStagingRootToRepositoryAndManifest() async throws {
        let fixture = makeVoiceInputTestModelDescriptor(dataByPath: ["bundle/model.bin": Data("model".utf8)])
        let modelsDirectory = temporaryDirectory.appendingPathComponent("staging-inventory-models", isDirectory: true)
        let stagingDirectory = modelsDirectory
            .appendingPathComponent(String(VoiceInputModelManifest.currentSchema), isDirectory: true)
            .appendingPathComponent(fixture.resolved.descriptor.revision, isDirectory: true)
            .appendingPathComponent("staging", isDirectory: true)
        let unexpectedDirectory = stagingDirectory.appendingPathComponent("unexpected", isDirectory: true)
        let unexpectedPipe = stagingDirectory.appendingPathComponent("unexpected.pipe")
        try FileManager.default.createDirectory(at: unexpectedDirectory, withIntermediateDirectories: true)
        try Data("unexpected".utf8).write(to: unexpectedDirectory.appendingPathComponent("file.bin"))
        XCTAssertEqual(Darwin.mkfifo(unexpectedPipe.path, 0o600), 0)
        let repository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)

        let prepared = try await repository.prepareModel(mode: .normal) { _ in }

        let validatedDirectory = prepared.repositoryDirectory.deletingLastPathComponent()
        let validatedEntries = try FileManager.default.contentsOfDirectory(
            at: validatedDirectory,
            includingPropertiesForKeys: nil
        ).map(\.lastPathComponent)
        XCTAssertEqual(Set(validatedEntries), Set(["manifest.json", "repository"]))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpectedDirectory.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpectedPipe.path))
    }

    func testValidatedRepositoryRejectsUnexpectedDirectoriesAndSpecialNodes() async throws {
        for entryKind in UnexpectedRepositoryEntryKind.allCases {
            let fixture = makeVoiceInputTestModelDescriptor(dataByPath: ["bundle/model.bin": Data("model".utf8)])
            let modelsDirectory = temporaryDirectory.appendingPathComponent(
                "validated-inventory-\(entryKind.rawValue)",
                isDirectory: true
            )
            let initialRepository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)
            let initialModel = try await initialRepository.prepareModel(mode: .normal) { _ in }
            let unexpectedURL = initialModel.repositoryDirectory.appendingPathComponent("unexpected-\(entryKind.rawValue)")
            try entryKind.create(at: unexpectedURL)
            let downloader = VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath)
            let reopenedRepository = DefaultVoiceInputModelRepository(
                modelsDirectory: modelsDirectory,
                cacheOwnershipDirectory: temporaryDirectory,
                descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
                downloader: downloader,
                diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
            )

            let recovered = try await reopenedRepository.prepareModel(mode: .normal) { _ in }

            let downloadCount = await downloader.downloadCount
            XCTAssertEqual(downloadCount, 1, entryKind.rawValue)
            XCTAssertFalse(FileManager.default.fileExists(atPath: unexpectedURL.path), entryKind.rawValue)
            XCTAssertTrue(FileManager.default.fileExists(
                atPath: recovered.repositoryDirectory.appendingPathComponent("bundle/model.bin").path
            ))
        }
    }

    func testValidatedCacheRejectsUnexpectedRootEntry() async throws {
        let fixture = makeVoiceInputTestModelDescriptor(dataByPath: ["bundle/model.bin": Data("model".utf8)])
        let modelsDirectory = temporaryDirectory.appendingPathComponent("validated-root-inventory", isDirectory: true)
        let initialRepository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)
        let initialModel = try await initialRepository.prepareModel(mode: .normal) { _ in }
        let unexpectedURL = initialModel.repositoryDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("unexpected.bin")
        try Data("unexpected".utf8).write(to: unexpectedURL)
        let downloader = VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath)
        let reopenedRepository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: temporaryDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
            downloader: downloader,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        let recovered = try await reopenedRepository.prepareModel(mode: .normal) { _ in }
        let downloadCount = await downloader.downloadCount

        XCTAssertEqual(downloadCount, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: unexpectedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: recovered.repositoryDirectory.appendingPathComponent("bundle/model.bin").path
        ))
    }

    func testCancelledRepairPreservesValidatedAndResumableCacheData() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let modelsDirectory = temporaryDirectory.appendingPathComponent("cancelled-repair-models", isDirectory: true)
        let repository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)
        let prepared = try await repository.prepareModel(mode: .normal) { _ in }
        let revisionDirectory = prepared.repositoryDirectory
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let resumableURL = revisionDirectory.appendingPathComponent("staging/resume.bin")
        try FileManager.default.createDirectory(
            at: resumableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("resume".utf8).write(to: resumableURL)
        let gate = VoiceInputRepositoryCancellationGate()
        let operation = Task {
            await gate.wait()
            return try await repository.prepareModel(mode: .repair) { _ in }
        }
        for _ in 0..<500 {
            if await gate.hasWaiter {
                break
            }
            await Task.yield()
        }
        let gateHasWaiter = await gate.hasWaiter
        XCTAssertTrue(gateHasWaiter)
        operation.cancel()
        await gate.release()

        do {
            _ = try await operation.value
            XCTFail("Expected cancelled repair")
        } catch is CancellationError {
            // Expected.
        }

        let artifact = try XCTUnwrap(fixture.resolved.descriptor.artifacts.first)
        let expectedArtifactData = try XCTUnwrap(fixture.dataByPath[artifact.path])
        XCTAssertEqual(
            try Data(contentsOf: prepared.repositoryDirectory.appendingPathComponent(artifact.path)),
            expectedArtifactData
        )
        XCTAssertEqual(try Data(contentsOf: resumableURL), Data("resume".utf8))
    }

    func testValidatedRepositoryRootSymlinkIsRejectedWithoutTouchingExternalTarget() async throws {
        let fixture = makeVoiceInputTestModelDescriptor()
        let modelsDirectory = temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
        let initialRepository = makeContainmentRepository(modelsDirectory: modelsDirectory, fixture: fixture)
        let initialModel = try await initialRepository.prepareModel(mode: .normal) { _ in }
        let externalDirectory = temporaryDirectory.appendingPathComponent("external-validated-repository", isDirectory: true)
        let externalRepository = externalDirectory.appendingPathComponent("repository", isDirectory: true)
        let sentinel = externalDirectory.appendingPathComponent("sentinel.txt")
        try FileManager.default.createDirectory(at: externalRepository, withIntermediateDirectories: true)
        for (path, data) in fixture.dataByPath {
            let artifactURL = externalRepository.appendingPathComponent(path)
            try FileManager.default.createDirectory(
                at: artifactURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: artifactURL)
        }
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.removeItem(at: initialModel.repositoryDirectory)
        try FileManager.default.createSymbolicLink(
            at: initialModel.repositoryDirectory,
            withDestinationURL: externalRepository
        )
        let downloader = VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath)
        let reopenedRepository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: temporaryDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
            downloader: downloader,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        let recoveredModel = try await reopenedRepository.prepareModel(mode: .normal) { _ in }
        let downloadCount = await downloader.downloadCount

        XCTAssertEqual(downloadCount, 1)
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: recoveredModel.repositoryDirectory.path)[.type]
                as? FileAttributeType,
            .typeDirectory
        )
    }

    private func makeContainmentRepository(
        modelsDirectory: URL,
        fixture: VoiceInputTestModelDescriptor
    ) -> DefaultVoiceInputModelRepository {
        DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: temporaryDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: fixture.resolved),
            downloader: VoiceInputModelDownloaderFake(artifactData: fixture.dataByPath),
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )
    }
}

private enum UnexpectedRepositoryEntryKind: String, CaseIterable {
    case directory
    case namedPipe

    func create(at url: URL) throws {
        switch self {
        case .directory:
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        case .namedPipe:
            guard Darwin.mkfifo(url.path, 0o600) == 0 else {
                throw POSIXError(.EIO)
            }
        }
    }
}

private actor VoiceInputRepositoryCancellationGate {
    private var continuation: CheckedContinuation<Void, Never>?

    var hasWaiter: Bool {
        continuation != nil
    }

    func wait() async {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func release() {
        let continuation = continuation
        self.continuation = nil
        continuation?.resume()
    }
}
