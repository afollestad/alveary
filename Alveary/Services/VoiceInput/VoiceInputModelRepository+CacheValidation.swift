import Foundation

extension DefaultVoiceInputModelRepository {
    func repositoryMatchesDescriptor(
        _ repositoryDirectory: URL,
        descriptor: VoiceInputPinnedModelDescriptor
    ) throws -> Bool {
        try validateCachePathAncestors(of: repositoryDirectory)
        guard try cacheEntryIsDirectory(repositoryDirectory) else { return false }
        guard let enumerator = fileManager.enumerator(
            at: repositoryDirectory,
            includingPropertiesForKeys: [.fileSizeKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            return false
        }
        let artifactsByPath = Dictionary(uniqueKeysWithValues: descriptor.artifacts.map { ($0.path, $0) })
        let expectedDirectoryPaths = VoiceInputModelArtifactInventory.expectedDirectoryPaths(for: descriptor.artifacts)
        let rootPath = repositoryDirectory.standardizedFileURL.path
        var seenPaths = Set<String>()
        var seenDirectoryPaths = Set<String>()
        for case let url as URL in enumerator {
            let values = try url.resourceValues(
                forKeys: [.fileSizeKey, .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey]
            )
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                return false
            }
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("\(rootPath)/") else { return false }
            let relativePath = String(path.dropFirst(rootPath.count + 1))
            if values.isDirectory == true {
                guard expectedDirectoryPaths.contains(relativePath),
                      seenDirectoryPaths.insert(relativePath).inserted else {
                    return false
                }
                continue
            }
            guard values.isRegularFile == true else { return false }
            guard let artifact = artifactsByPath[relativePath],
                  let size = values.fileSize,
                  Int64(size) == artifact.size,
                  seenPaths.insert(relativePath).inserted,
                  try VoiceInputModelArtifactIntegrity.contentHash(of: url, artifact: artifact) else {
                return false
            }
        }
        return seenPaths == Set(artifactsByPath.keys) && seenDirectoryPaths == expectedDirectoryPaths
    }

    func normalizeStagingContainer(_ stagingDirectory: URL) throws {
        guard try cacheEntryIsDirectory(stagingDirectory) else { return }
        for entry in try fileManager.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil) {
            let type = try fileManager.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType
            let isAllowed = switch entry.lastPathComponent {
            case Self.repositoryFolder:
                type == .typeDirectory
            case Self.manifestFile:
                type == .typeRegular
            default:
                false
            }
            if !isAllowed {
                try removeIfPresent(entry)
            }
        }
    }

    func cacheContainerHasExactInventory(
        _ directory: URL,
        requiresManifest: Bool
    ) throws -> Bool {
        try validateCachePathAncestors(of: directory)
        guard try cacheEntryIsDirectory(directory) else { return false }
        var hasRepository = false
        var hasManifest = false
        for entry in try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            let type = try fileManager.attributesOfItem(atPath: entry.path)[.type] as? FileAttributeType
            switch entry.lastPathComponent {
            case Self.repositoryFolder where type == .typeDirectory:
                hasRepository = true
            case Self.manifestFile where type == .typeRegular:
                hasManifest = true
            default:
                return false
            }
        }
        return hasRepository && (!requiresManifest || hasManifest)
    }

    func paths(for descriptor: VoiceInputPinnedModelDescriptor) -> CachePaths {
        let revisionDirectory = modelsDirectory
            .appendingPathComponent(String(VoiceInputModelManifest.currentSchema), isDirectory: true)
            .appendingPathComponent(descriptor.revision, isDirectory: true)
        return CachePaths(
            revision: revisionDirectory,
            staging: revisionDirectory.appendingPathComponent("staging", isDirectory: true),
            validated: revisionDirectory.appendingPathComponent("validated", isDirectory: true)
        )
    }

    var currentSchemaDirectory: URL {
        modelsDirectory.appendingPathComponent(String(VoiceInputModelManifest.currentSchema), isDirectory: true)
    }

    func prepareRootDirectory() throws {
        try removeInvalidCacheDirectoryEntry(modelsDirectory)
        try fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = modelsDirectory
        try mutableDirectory.setResourceValues(values)
    }

    func hasPreviousModel(excluding revision: String) throws -> Bool {
        guard fileManager.fileExists(atPath: modelsDirectory.path) else { return false }
        let schemaName = String(VoiceInputModelManifest.currentSchema)
        for item in try fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil) {
            if item.lastPathComponent != schemaName {
                return true
            }
            for revisionItem in try fileManager.contentsOfDirectory(at: item, includingPropertiesForKeys: nil)
            where revisionItem.lastPathComponent != revision {
                return true
            }
        }
        return false
    }

    func removeLegacyLayouts() throws {
        guard fileManager.fileExists(atPath: modelsDirectory.path) else { return }
        let currentSchema = String(VoiceInputModelManifest.currentSchema)
        for item in try fileManager.contentsOfDirectory(at: modelsDirectory, includingPropertiesForKeys: nil)
        where item.lastPathComponent != currentSchema {
            try removeIfPresent(item)
        }
    }

    func removeIfPresent(_ url: URL) throws {
        try validateCachePathAncestors(of: url)
        try VoiceInputModelFileError.removeIfPresent(url, fileManager: fileManager)
    }

    func removeInvalidCacheDirectoryEntry(_ url: URL) throws {
        try validateCachePathAncestors(of: url)
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType != .typeDirectory else { return }
            try removeIfPresent(url)
        } catch where VoiceInputModelFileError.isNoSuchFile(error) {
            return
        }
    }

    func cacheDirectoryIsSafeAndExists(_ url: URL) throws -> Bool {
        try validateCachePathAncestors(of: url)
        try removeInvalidCacheDirectoryEntry(url)
        return fileManager.fileExists(atPath: url.path)
    }

    func cacheEntryIsDirectory(_ url: URL) throws -> Bool {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            return attributes[.type] as? FileAttributeType == .typeDirectory
        } catch where VoiceInputModelFileError.isNoSuchFile(error) {
            return false
        }
    }

    func validateCachePathAncestors(of targetURL: URL) throws {
        let targetURL = targetURL.standardizedFileURL
        guard modelsDirectory.isEqualToOrDescendant(of: cacheOwnershipDirectory),
              targetURL.isEqualToOrDescendant(of: modelsDirectory) else {
            throw unsafeCachePathError
        }
        try validateCacheOwnershipDirectoryIfPresent()

        let parentURL = targetURL.deletingLastPathComponent().standardizedFileURL
        guard parentURL.isEqualToOrDescendant(of: cacheOwnershipDirectory) else {
            return
        }
        let ownershipComponents = cacheOwnershipDirectory.pathComponents
        let parentComponents = parentURL.pathComponents
        guard parentComponents.starts(with: ownershipComponents) else {
            throw unsafeCachePathError
        }

        var currentURL = cacheOwnershipDirectory
        for component in parentComponents.dropFirst(ownershipComponents.count) {
            currentURL.appendPathComponent(component, isDirectory: true)
            do {
                let attributes = try fileManager.attributesOfItem(atPath: currentURL.path)
                guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                    throw unsafeCachePathError
                }
            } catch where VoiceInputModelFileError.isNoSuchFile(error) {
                return
            }
        }
    }

    func validateCacheOwnershipDirectoryIfPresent() throws {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: cacheOwnershipDirectory.path)
            guard attributes[.type] as? FileAttributeType == .typeDirectory else {
                throw unsafeCachePathError
            }
        } catch where VoiceInputModelFileError.isNoSuchFile(error) {
            return
        }
    }

    var unsafeCachePathError: VoiceInputServiceError {
        .modelCache("The voice model cache path contains an unsafe symbolic link.")
    }
}

private extension URL {
    func isEqualToOrDescendant(of directory: URL) -> Bool {
        standardizedFileURL.pathComponents.starts(with: directory.standardizedFileURL.pathComponents)
    }
}
