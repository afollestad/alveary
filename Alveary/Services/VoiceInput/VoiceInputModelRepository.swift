import Foundation

protocol VoiceInputDiskSpaceProviding: Sendable {
    func availableCapacity(at directory: URL) throws -> Int64?
}

struct VolumeVoiceInputDiskSpaceProvider: VoiceInputDiskSpaceProviding {
    func availableCapacity(at directory: URL) throws -> Int64? {
        let values = try directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        return values.volumeAvailableCapacityForImportantUsage
    }
}

actor DefaultVoiceInputModelRepository: VoiceInputModelRepository {
    struct CachePaths {
        let revision: URL
        let staging: URL
        let validated: URL
    }

    struct CachePreparation {
        let preparedModel: VoiceInputPreparedModel?
        let paths: CachePaths
        let preparationKind: VoiceInputModelPreparationKind
    }

    static let repositoryFolder = "repository"
    static let manifestFile = "manifest.json"

    let modelsDirectory: URL
    let cacheOwnershipDirectory: URL
    private let descriptorProvider: any VoiceInputModelDescriptorProviding
    private let downloader: any VoiceInputModelDownloading
    private let diskSpaceProvider: any VoiceInputDiskSpaceProviding
    let fileManager: FileManager
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(
        modelsDirectory: URL,
        cacheOwnershipDirectory: URL,
        descriptorProvider: any VoiceInputModelDescriptorProviding = BundledVoiceInputModelDescriptorProvider(),
        downloader: any VoiceInputModelDownloading = PinnedVoiceInputModelDownloader(),
        diskSpaceProvider: any VoiceInputDiskSpaceProviding = VolumeVoiceInputDiskSpaceProvider(),
        fileManager: FileManager = .default
    ) {
        self.modelsDirectory = modelsDirectory.standardizedFileURL
        self.cacheOwnershipDirectory = cacheOwnershipDirectory.standardizedFileURL
        self.descriptorProvider = descriptorProvider
        self.downloader = downloader
        self.diskSpaceProvider = diskSpaceProvider
        self.fileManager = fileManager
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    }

    func prepareModel(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel {
        do {
            return try await prepareModelWithoutErrorMapping(mode: mode, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as VoiceInputServiceError {
            throw error
        } catch {
            throw VoiceInputModelFileError.cacheError(for: error)
        }
    }

    func purgeValidatedModel() async throws {
        do {
            try Task.checkCancellation()
            let descriptor = try descriptorProvider.loadDescriptor()
            try Task.checkCancellation()
            let cachePaths = paths(for: descriptor.descriptor)
            guard try cacheDirectoryIsSafeAndExists(modelsDirectory),
                  try cacheDirectoryIsSafeAndExists(currentSchemaDirectory),
                  try cacheDirectoryIsSafeAndExists(cachePaths.revision) else {
                return
            }
            try removeIfPresent(cachePaths.validated)
        } catch let error as VoiceInputServiceError {
            throw error
        } catch {
            throw VoiceInputModelFileError.cacheError(for: error)
        }
    }

    func removeUnpinnedModels() async throws {
        do {
            let descriptor = try descriptorProvider.loadDescriptor().descriptor
            guard try cacheDirectoryIsSafeAndExists(modelsDirectory) else { return }
            let schemaDirectory = modelsDirectory.appendingPathComponent(
                String(VoiceInputModelManifest.currentSchema),
                isDirectory: true
            )
            guard try cacheDirectoryIsSafeAndExists(schemaDirectory) else { return }
            for url in try fileManager.contentsOfDirectory(
                at: schemaDirectory,
                includingPropertiesForKeys: nil
            ) where url.lastPathComponent != descriptor.revision {
                try removeIfPresent(url)
            }
        } catch let error as VoiceInputServiceError {
            throw error
        } catch {
            throw VoiceInputModelFileError.cacheError(for: error)
        }
    }

    func purgeAllModels() async throws {
        do {
            try removeIfPresent(modelsDirectory)
        } catch let error as VoiceInputServiceError {
            throw error
        } catch {
            throw VoiceInputModelFileError.cacheError(for: error)
        }
    }

    private func prepareModelWithoutErrorMapping(
        mode: VoiceInputModelPreparationMode,
        progress: @escaping VoiceInputPreparationProgressHandler
    ) async throws -> VoiceInputPreparedModel {
        try Task.checkCancellation()
        let resolvedDescriptor = try descriptorProvider.loadDescriptor()
        try Task.checkCancellation()
        try prepareRootDirectory()
        progress(.checkingModel)

        let cache = try prepareCache(resolvedDescriptor: resolvedDescriptor, mode: mode)
        if let cached = cache.preparedModel {
            return cached
        }
        let descriptor = resolvedDescriptor.descriptor
        let stagingRepository = cache.paths.staging.appendingPathComponent(Self.repositoryFolder, isDirectory: true)
        try VoiceInputModelDiskSpacePreflight(
            fileManager: fileManager,
            diskSpaceProvider: diskSpaceProvider
        ).validate(
            artifacts: descriptor.artifacts,
            repositoryDirectory: stagingRepository,
            modelsDirectory: modelsDirectory
        )

        let downloadProgress = CoalescingVoiceInputDownloadProgress { fraction in
            progress(.downloading(kind: cache.preparationKind, fraction: fraction))
        }
        progress(.downloading(kind: cache.preparationKind, fraction: 0))
        try await download(
            descriptor: descriptor,
            to: stagingRepository,
            progress: downloadProgress.report
        )
        try Task.checkCancellation()
        let promoted = try validateAndPromote(
            resolvedDescriptor: resolvedDescriptor,
            paths: cache.paths,
            preparationKind: cache.preparationKind
        )
        return promoted
    }

    private func prepareCache(
        resolvedDescriptor: VoiceInputResolvedModelDescriptor,
        mode: VoiceInputModelPreparationMode
    ) throws -> CachePreparation {
        try Task.checkCancellation()
        try removeInvalidCacheDirectoryEntry(currentSchemaDirectory)
        let hadPreviousModel = try hasPreviousModel(excluding: resolvedDescriptor.descriptor.revision)
        try removeLegacyLayouts()
        let cachePaths = paths(for: resolvedDescriptor.descriptor)
        try removeInvalidCacheDirectoryEntry(cachePaths.revision)
        try removeInvalidCacheDirectoryEntry(cachePaths.validated)
        try removeInvalidCacheDirectoryEntry(cachePaths.staging)
        if mode == .repair {
            try Task.checkCancellation()
            try removeIfPresent(cachePaths.validated)
            try removeIfPresent(cachePaths.staging)
        } else {
            try normalizeStagingContainer(cachePaths.staging)
            if let cached = try validatedModelIfValid(
                resolvedDescriptor: resolvedDescriptor,
                at: cachePaths.validated
            ) {
                return CachePreparation(preparedModel: cached, paths: cachePaths, preparationKind: .installation)
            }
            try removeIfPresent(cachePaths.validated)
        }
        let kind: VoiceInputModelPreparationKind = mode == .repair ? .repair : (hadPreviousModel ? .update : .installation)
        return CachePreparation(preparedModel: nil, paths: cachePaths, preparationKind: kind)
    }

    private func download(
        descriptor: VoiceInputPinnedModelDescriptor,
        to repositoryDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        do {
            try await downloader.download(
                descriptor: descriptor,
                to: repositoryDirectory,
                progress: progress
            )
        } catch let error where VoiceInputModelFileError.isCancellation(error) {
            throw CancellationError()
        } catch {
            if VoiceInputModelFileError.isDiskFull(error) {
                throw VoiceInputServiceError.diskFull
            }
            if VoiceInputModelFileError.isLocalFileSystemError(error) {
                throw VoiceInputServiceError.modelCache(error.localizedDescription)
            }
            throw mappedVoiceInputError(error, fallback: .modelDownload(error.localizedDescription))
        }
    }

    private func validateAndPromote(
        resolvedDescriptor: VoiceInputResolvedModelDescriptor,
        paths: CachePaths,
        preparationKind: VoiceInputModelPreparationKind
    ) throws -> VoiceInputPreparedModel {
        let descriptor = resolvedDescriptor.descriptor
        let repositoryDirectory = paths.staging.appendingPathComponent(Self.repositoryFolder, isDirectory: true)
        guard try cacheContainerHasExactInventory(paths.staging, requiresManifest: false),
              try repositoryMatchesDescriptor(repositoryDirectory, descriptor: descriptor) else {
            throw VoiceInputServiceError.modelCache("The downloaded voice model repository is incomplete or invalid.")
        }

        let manifest = VoiceInputModelManifest(
            schema: VoiceInputModelManifest.currentSchema,
            fluidAudioRevision: VoiceInputModelManifest.fluidAudioRevision,
            repository: descriptor.repository,
            modelRevision: descriptor.revision,
            descriptorSHA256: resolvedDescriptor.sha256,
            configuration: descriptor.configuration,
            artifacts: descriptor.artifacts
        )
        try fileManager.createDirectory(at: paths.staging, withIntermediateDirectories: true)
        try encoder.encode(manifest).write(
            to: paths.staging.appendingPathComponent(Self.manifestFile),
            options: .atomic
        )
        guard try cacheContainerHasExactInventory(paths.staging, requiresManifest: true) else {
            throw VoiceInputServiceError.modelCache("The downloaded voice model staging directory is invalid.")
        }
        try removeIfPresent(paths.validated)
        try fileManager.createDirectory(
            at: paths.validated.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: paths.staging, to: paths.validated)
        return VoiceInputPreparedModel(
            repositoryDirectory: paths.validated.appendingPathComponent(Self.repositoryFolder, isDirectory: true),
            manifest: manifest,
            source: .downloaded(preparationKind)
        )
    }

    private func validatedModelIfValid(
        resolvedDescriptor: VoiceInputResolvedModelDescriptor,
        at validatedDirectory: URL
    ) throws -> VoiceInputPreparedModel? {
        guard try cacheContainerHasExactInventory(validatedDirectory, requiresManifest: true) else {
            return nil
        }
        let manifestURL = validatedDirectory.appendingPathComponent(Self.manifestFile)
        let data = try Data(contentsOf: manifestURL)
        guard let manifest = try? decoder.decode(VoiceInputModelManifest.self, from: data),
              manifestMatches(manifest, resolvedDescriptor: resolvedDescriptor) else {
            return nil
        }
        let repositoryDirectory = validatedDirectory.appendingPathComponent(Self.repositoryFolder, isDirectory: true)
        guard try repositoryMatchesDescriptor(
            repositoryDirectory,
            descriptor: resolvedDescriptor.descriptor
        ) else {
            return nil
        }
        return VoiceInputPreparedModel(
            repositoryDirectory: repositoryDirectory,
            manifest: manifest,
            source: .validatedCache
        )
    }

    private func manifestMatches(
        _ manifest: VoiceInputModelManifest,
        resolvedDescriptor: VoiceInputResolvedModelDescriptor
    ) -> Bool {
        let descriptor = resolvedDescriptor.descriptor
        return manifest.schema == VoiceInputModelManifest.currentSchema &&
            manifest.fluidAudioRevision == VoiceInputModelManifest.fluidAudioRevision &&
            manifest.repository == descriptor.repository &&
            manifest.modelRevision == descriptor.revision &&
            manifest.descriptorSHA256 == resolvedDescriptor.sha256 &&
            manifest.configuration == descriptor.configuration &&
            manifest.artifacts == descriptor.artifacts
    }
}
