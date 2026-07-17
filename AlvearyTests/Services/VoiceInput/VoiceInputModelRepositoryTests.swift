@testable import Alveary
import Foundation
import XCTest

final class VoiceInputModelRepositoryTests: XCTestCase {
    var temporaryDirectory: URL!

    override func setUpWithError() throws {
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("VoiceInputModelRepositoryTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        temporaryDirectory = nil
    }

    func testValidatedPinnedCacheLoadsOfflineWithoutDownloading() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let firstDownloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let firstRepository = makeRepository(model: model, downloader: firstDownloader)
        let first = try await firstRepository.prepareModel(mode: .normal) { _ in }

        let offlineDownloader = VoiceInputModelDownloaderFake(
            artifactData: model.dataByPath,
            failure: .network
        )
        let secondRepository = makeRepository(model: model, downloader: offlineDownloader)
        let second = try await secondRepository.prepareModel(mode: .normal) { _ in }
        let firstDownloadCount = await firstDownloader.downloadCount
        let offlineDownloadCount = await offlineDownloader.downloadCount

        XCTAssertEqual(first.repositoryDirectory, second.repositoryDirectory)
        XCTAssertEqual(first.manifest, second.manifest)
        XCTAssertEqual(first.source, .downloaded(.installation))
        XCTAssertEqual(second.source, .validatedCache)
        XCTAssertEqual(firstDownloadCount, 1)
        XCTAssertEqual(offlineDownloadCount, 0)
    }

    func testPromotedManifestStoresPinnedIdentityAndDescriptorDigest() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let repository = makeRepository(
            model: model,
            downloader: VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        )

        let prepared = try await repository.prepareModel(mode: .normal) { _ in }

        XCTAssertEqual(prepared.manifest.modelRevision, model.resolved.descriptor.revision)
        XCTAssertEqual(prepared.manifest.descriptorSHA256, model.resolved.sha256)
        XCTAssertEqual(prepared.manifest.repository, model.resolved.descriptor.repository)
        XCTAssertEqual(prepared.manifest.configuration, model.resolved.descriptor.configuration)
        XCTAssertEqual(prepared.manifest.artifacts, model.resolved.descriptor.artifacts)
        XCTAssertEqual(prepared.source, .downloaded(.installation))
    }

    func testRevisionUpdateKeepsOldPinUntilExplicitPostLoadCleanup() async throws {
        let oldModel = makeVoiceInputTestModelDescriptor(revision: String(repeating: "a", count: 40))
        let oldRepository = makeRepository(
            model: oldModel,
            downloader: VoiceInputModelDownloaderFake(artifactData: oldModel.dataByPath)
        )
        _ = try await oldRepository.prepareModel(mode: .normal) { _ in }

        let newModel = makeVoiceInputTestModelDescriptor(
            revision: String(repeating: "b", count: 40),
            dataByPath: ["model.bin": Data("new model".utf8)]
        )
        let newRepository = makeRepository(
            model: newModel,
            downloader: VoiceInputModelDownloaderFake(artifactData: newModel.dataByPath)
        )
        let progress = VoiceInputProgressRecorder()
        let prepared = try await newRepository.prepareModel(mode: .normal, progress: progress.append)

        XCTAssertTrue(FileManager.default.fileExists(atPath: validatedDirectory(for: oldModel).path))
        XCTAssertTrue(progress.values.contains(.downloading(kind: .update, fraction: 0)))
        XCTAssertEqual(prepared.source, .downloaded(.update))

        try await newRepository.removeUnpinnedModels()

        XCTAssertFalse(FileManager.default.fileExists(atPath: validatedDirectory(for: oldModel).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: validatedDirectory(for: newModel).path))
    }

    func testLegacyUnpinnedLayoutIsRemovedBeforePinnedInstallation() async throws {
        let legacy = temporaryDirectory.appendingPathComponent("1/validated", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("legacy".utf8).write(to: legacy.appendingPathComponent("model.bin"))
        let model = makeVoiceInputTestModelDescriptor()
        let repository = makeRepository(
            model: model,
            downloader: VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        )
        let progress = VoiceInputProgressRecorder()

        _ = try await repository.prepareModel(mode: .normal, progress: progress.append)

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.appendingPathComponent("1").path))
        XCTAssertTrue(progress.values.contains(.downloading(kind: .update, fraction: 0)))
    }

    func testRepairPurgesAndRedownloadsSamePinnedRevision() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let downloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let repository = makeRepository(model: model, downloader: downloader)
        _ = try await repository.prepareModel(mode: .normal) { _ in }
        let progress = VoiceInputProgressRecorder()

        let repaired = try await repository.prepareModel(mode: .repair, progress: progress.append)
        let downloadCount = await downloader.downloadCount

        XCTAssertEqual(repaired.manifest.modelRevision, model.resolved.descriptor.revision)
        XCTAssertEqual(repaired.source, .downloaded(.repair))
        XCTAssertEqual(downloadCount, 2)
        XCTAssertTrue(progress.values.contains(.downloading(kind: .repair, fraction: 0)))
    }

    func testCancellationPreservesRevisionScopedPartWithoutPromotion() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let repository = makeRepository(
            model: model,
            downloader: VoiceInputModelDownloaderFake(
                artifactData: model.dataByPath,
                failure: .cancellation
            )
        )

        do {
            _ = try await repository.prepareModel(mode: .normal) { _ in }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        let part = stagingRepository(for: model).appendingPathComponent("model.bin.part")
        XCTAssertTrue(FileManager.default.fileExists(atPath: part.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: validatedDirectory(for: model).path))
    }

    func testCorruptValidatedCacheIsPurgedAndRedownloaded() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let initial = makeRepository(
            model: model,
            downloader: VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        )
        let prepared = try await initial.prepareModel(mode: .normal) { _ in }
        try Data("corrupt".utf8).write(to: prepared.repositoryDirectory.appendingPathComponent("model.bin"))
        let repairDownloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let reopened = makeRepository(model: model, downloader: repairDownloader)

        _ = try await reopened.prepareModel(mode: .normal) { _ in }
        let downloadCount = await repairDownloader.downloadCount

        XCTAssertEqual(downloadCount, 1)
    }

    func testSameRepositoryInstanceRevalidatesCorruptPreparedCache() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let downloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let repository = makeRepository(model: model, downloader: downloader)
        let prepared = try await repository.prepareModel(mode: .normal) { _ in }
        try Data("corrupt".utf8).write(to: prepared.repositoryDirectory.appendingPathComponent("model.bin"))

        _ = try await repository.prepareModel(mode: .normal) { _ in }
        let downloadCount = await downloader.downloadCount

        XCTAssertEqual(downloadCount, 2)
    }

    func testDanglingValidatedCacheSymlinkIsRemovedAndReplaced() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let validatedDirectory = validatedDirectory(for: model)
        try FileManager.default.createDirectory(
            at: validatedDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: validatedDirectory,
            withDestinationURL: temporaryDirectory.appendingPathComponent("missing-validated-cache")
        )
        let downloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let repository = makeRepository(model: model, downloader: downloader)

        let prepared = try await repository.prepareModel(mode: .normal) { _ in }
        let downloadCount = await downloader.downloadCount

        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.repositoryDirectory.path))
        XCTAssertEqual(downloadCount, 1)
    }

    func testDanglingStagingCacheSymlinkIsRemovedAndReplaced() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let stagingDirectory = stagingRepository(for: model).deletingLastPathComponent()
        try FileManager.default.createDirectory(
            at: stagingDirectory.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: stagingDirectory,
            withDestinationURL: temporaryDirectory.appendingPathComponent("missing-staging-cache")
        )
        let downloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let repository = makeRepository(model: model, downloader: downloader)

        let prepared = try await repository.prepareModel(mode: .normal) { _ in }
        let downloadCount = await downloader.downloadCount

        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.repositoryDirectory.path))
        XCTAssertEqual(downloadCount, 1)
    }

    func testModelCacheRootSymlinkIsReplacedWithoutTouchingExternalTarget() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let externalDirectory = temporaryDirectory.appendingPathComponent("external", isDirectory: true)
        let sentinel = externalDirectory.appendingPathComponent("sentinel.txt")
        let modelsDirectory = temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try Data("keep me".utf8).write(to: sentinel)
        try FileManager.default.createSymbolicLink(
            at: modelsDirectory,
            withDestinationURL: externalDirectory
        )
        let downloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let repository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: temporaryDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: model.resolved),
            downloader: downloader,
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        let prepared = try await repository.prepareModel(mode: .normal) { _ in }

        XCTAssertEqual(try Data(contentsOf: sentinel), Data("keep me".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: externalDirectory
                .appendingPathComponent(String(VoiceInputModelManifest.currentSchema), isDirectory: true)
                .path
        ))
        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.repositoryDirectory.path))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: modelsDirectory.path)[.type] as? FileAttributeType,
            .typeDirectory
        )
    }

    func testNonDirectoryModelCacheRootIsRemovedAndReplaced() async throws {
        let modelsDirectory = temporaryDirectory.appendingPathComponent("Models", isDirectory: true)
        try Data("stale cache entry".utf8).write(to: modelsDirectory)
        let model = makeVoiceInputTestModelDescriptor()
        let repository = DefaultVoiceInputModelRepository(
            modelsDirectory: modelsDirectory,
            cacheOwnershipDirectory: temporaryDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: model.resolved),
            downloader: VoiceInputModelDownloaderFake(artifactData: model.dataByPath),
            diskSpaceProvider: FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
        )

        let prepared = try await repository.prepareModel(mode: .normal) { _ in }

        XCTAssertTrue(FileManager.default.fileExists(atPath: prepared.repositoryDirectory.path))
        XCTAssertEqual(
            try FileManager.default.attributesOfItem(atPath: modelsDirectory.path)[.type] as? FileAttributeType,
            .typeDirectory
        )
    }

    func testDiskPreflightIncludesTemporaryFileMargin() async {
        let model = makeVoiceInputTestModelDescriptor()
        let downloader = VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        let repository = makeRepository(
            model: model,
            downloader: downloader,
            diskSpace: FixedVoiceInputDiskSpaceProvider(capacity: 512 * 1_024 * 1_024)
        )

        do {
            _ = try await repository.prepareModel(mode: .normal) { _ in }
            XCTFail("Expected disk-space failure")
        } catch let error as VoiceInputServiceError {
            guard case .insufficientDiskSpace = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
        let downloadCount = await downloader.downloadCount
        XCTAssertEqual(downloadCount, 0)
    }

    func testDiskExhaustionAndNetworkFailureHaveDistinctErrors() async {
        let model = makeVoiceInputTestModelDescriptor()
        let diskRepository = makeRepository(
            model: model,
            downloader: VoiceInputModelDownloaderFake(artifactData: model.dataByPath, failure: .diskFull)
        )
        await assertPreparationError(.diskFull, repository: diskRepository)

        let networkRepository = makeRepository(
            model: model,
            downloader: VoiceInputModelDownloaderFake(artifactData: model.dataByPath, failure: .network)
        )
        do {
            _ = try await networkRepository.prepareModel(mode: .normal) { _ in }
            XCTFail("Expected network failure")
        } catch let error as VoiceInputServiceError {
            guard case .modelDownload = error else { return XCTFail("Unexpected error: \(error)") }
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPurgeAllModelsRemovesValidatedAndStagingCaches() async throws {
        let model = makeVoiceInputTestModelDescriptor()
        let repository = makeRepository(
            model: model,
            downloader: VoiceInputModelDownloaderFake(artifactData: model.dataByPath)
        )
        _ = try await repository.prepareModel(mode: .normal) { _ in }

        try await repository.purgeAllModels()

        XCTAssertFalse(FileManager.default.fileExists(atPath: temporaryDirectory.path))
    }

    private func makeRepository(
        model: VoiceInputTestModelDescriptor,
        downloader: VoiceInputModelDownloaderFake,
        diskSpace: any VoiceInputDiskSpaceProviding = FixedVoiceInputDiskSpaceProvider(capacity: Int64.max)
    ) -> DefaultVoiceInputModelRepository {
        DefaultVoiceInputModelRepository(
            modelsDirectory: temporaryDirectory,
            cacheOwnershipDirectory: temporaryDirectory,
            descriptorProvider: StaticVoiceInputModelDescriptorProvider(resolvedDescriptor: model.resolved),
            downloader: downloader,
            diskSpaceProvider: diskSpace
        )
    }

    private func assertPreparationError(
        _ expected: VoiceInputServiceError,
        repository: DefaultVoiceInputModelRepository
    ) async {
        do {
            _ = try await repository.prepareModel(mode: .normal) { _ in }
            XCTFail("Expected preparation failure")
        } catch let error as VoiceInputServiceError {
            XCTAssertEqual(error, expected)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    private func revisionDirectory(for model: VoiceInputTestModelDescriptor) -> URL {
        temporaryDirectory
            .appendingPathComponent(String(VoiceInputModelManifest.currentSchema), isDirectory: true)
            .appendingPathComponent(model.resolved.descriptor.revision, isDirectory: true)
    }

    private func validatedDirectory(for model: VoiceInputTestModelDescriptor) -> URL {
        revisionDirectory(for: model).appendingPathComponent("validated", isDirectory: true)
    }

    private func stagingRepository(for model: VoiceInputTestModelDescriptor) -> URL {
        revisionDirectory(for: model).appendingPathComponent("staging/repository", isDirectory: true)
    }
}
