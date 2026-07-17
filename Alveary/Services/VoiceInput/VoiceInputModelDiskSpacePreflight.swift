import Foundation

struct VoiceInputModelDiskSpacePreflight {
    let fileManager: FileManager
    let diskSpaceProvider: any VoiceInputDiskSpaceProviding

    func validate(
        artifacts: [VoiceInputModelArtifact],
        repositoryDirectory: URL,
        modelsDirectory: URL
    ) throws {
        guard !artifacts.isEmpty else { return }
        guard VoiceInputModelSizePolicy.checkedArtifactTotal(artifacts) != nil else {
            throw invalidArtifactSizes()
        }
        try normalizeDirectoryEntry(repositoryDirectory)
        var remainingBytes: Int64 = 0
        for artifact in artifacts {
            try normalizeParentDirectories(of: artifact, in: repositoryDirectory)
            let localURL = repositoryDirectory.appendingPathComponent(artifact.path)
            let artifactBytes = try remainingArtifactBytes(artifact, at: localURL)
            guard let next = VoiceInputModelSizePolicy.checkedAdding(artifactBytes, to: remainingBytes) else {
                throw invalidArtifactSizes()
            }
            remainingBytes = next
        }
        guard let requiredBytes = VoiceInputModelSizePolicy.checkedRequiredBytes(for: remainingBytes) else {
            throw invalidArtifactSizes()
        }
        guard let availableBytes = try diskSpaceProvider.availableCapacity(at: modelsDirectory),
              availableBytes < requiredBytes else {
            return
        }
        throw VoiceInputServiceError.insufficientDiskSpace(
            requiredBytes: requiredBytes,
            availableBytes: availableBytes
        )
    }

    private func remainingArtifactBytes(
        _ artifact: VoiceInputModelArtifact,
        at localURL: URL
    ) throws -> Int64 {
        if let localSize = try regularFileSize(at: localURL) {
            if localSize == artifact.size,
               try VoiceInputModelArtifactIntegrity.contentHash(of: localURL, artifact: artifact) {
                try removeIfPresent(localURL.appendingPathExtension("part"))
                return 0
            }
            try removeIfPresent(localURL)
        }

        let partialURL = localURL.appendingPathExtension("part")
        guard let partialSize = try regularFileSize(at: partialURL) else {
            return artifact.size
        }
        if partialSize == artifact.size {
            if try VoiceInputModelArtifactIntegrity.contentHash(of: partialURL, artifact: artifact) {
                return 0
            }
            try removeIfPresent(partialURL)
            return artifact.size
        }
        guard partialSize > 0, partialSize < artifact.size else {
            try removeIfPresent(partialURL)
            return artifact.size
        }
        return artifact.size - partialSize
    }

    private func removeIfPresent(_ url: URL) throws {
        try VoiceInputModelFileError.removeIfPresent(url, fileManager: fileManager)
    }

    private func normalizeParentDirectories(
        of artifact: VoiceInputModelArtifact,
        in repositoryDirectory: URL
    ) throws {
        var parent = repositoryDirectory
        for component in artifact.path.split(separator: "/").dropLast() {
            parent.appendPathComponent(String(component), isDirectory: true)
            guard try normalizeDirectoryEntry(parent) else {
                return
            }
        }
    }

    @discardableResult
    private func normalizeDirectoryEntry(_ url: URL) throws -> Bool {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch where VoiceInputModelFileError.isNoSuchFile(error) {
            return false
        }
        guard attributes[.type] as? FileAttributeType == .typeDirectory else {
            try removeIfPresent(url)
            return false
        }
        return true
    }

    private func regularFileSize(at url: URL) throws -> Int64? {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch where VoiceInputModelFileError.isNoSuchFile(error) {
            return nil
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let fileSize = (attributes[.size] as? NSNumber)?.int64Value else {
            try removeIfPresent(url)
            return nil
        }
        return fileSize
    }

    private func invalidArtifactSizes() -> VoiceInputServiceError {
        .modelCache("The voice model descriptor artifact sizes are invalid.")
    }
}
