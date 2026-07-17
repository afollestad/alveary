import Foundation

protocol VoiceInputModelDownloading: Sendable {
    func download(
        descriptor: VoiceInputPinnedModelDescriptor,
        to repositoryDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws
}

struct VoiceInputHTTPDownloadResult: Equatable, Sendable {
    let statusCode: Int
    let headers: [String: String]
    let finalURL: URL?
}

protocol VoiceInputHTTPDownloading: Sendable {
    func download(
        request: URLRequest,
        to partialURL: URL,
        expectedSize: Int64,
        existingBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> VoiceInputHTTPDownloadResult
}

protocol VoiceInputDownloadRetrySleeping: Sendable {
    func sleep(seconds: TimeInterval) async throws
}

struct ContinuousVoiceInputDownloadRetrySleeper: VoiceInputDownloadRetrySleeping {
    func sleep(seconds: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(seconds))
    }
}

struct PinnedVoiceInputModelDownloader: VoiceInputModelDownloading, @unchecked Sendable {
    let baseURL: URL
    let httpDownloader: any VoiceInputHTTPDownloading
    let retrySleeper: any VoiceInputDownloadRetrySleeping
    let fileManager: FileManager

    init(
        baseURL: URL? = nil,
        httpDownloader: any VoiceInputHTTPDownloading = URLSessionVoiceInputHTTPDownloader(),
        retrySleeper: any VoiceInputDownloadRetrySleeping = ContinuousVoiceInputDownloadRetrySleeper(),
        fileManager: FileManager = .default
    ) {
        self.baseURL = baseURL ?? Self.makeDefaultBaseURL()
        self.httpDownloader = httpDownloader
        self.retrySleeper = retrySleeper
        self.fileManager = fileManager
    }

    func download(
        descriptor: VoiceInputPinnedModelDescriptor,
        to repositoryDirectory: URL,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws {
        guard let totalSize = descriptor.totalSize else {
            throw VoiceInputServiceError.modelCache("The voice model descriptor artifact sizes are invalid.")
        }
        try prepareRepositoryDirectory(repositoryDirectory)
        try removeUnexpectedEntries(in: repositoryDirectory, artifacts: descriptor.artifacts)

        let reporter = CoalescingVoiceInputDownloadProgress(progress: progress)
        var completedBytes = try validatedCompletedBytes(
            artifacts: descriptor.artifacts,
            repositoryDirectory: repositoryDirectory
        )
        reporter.report(Double(completedBytes) / Double(totalSize))

        for artifact in descriptor.artifacts {
            try Task.checkCancellation()
            let finalURL = repositoryDirectory.appendingPathComponent(artifact.path)
            if try completedArtifactIsValid(artifact, at: finalURL) {
                try removeIfPresent(finalURL.appendingPathExtension("part"))
                continue
            }
            try await download(
                artifact,
                context: ArtifactDownloadContext(
                    descriptor: descriptor,
                    finalURL: finalURL,
                    completedBytes: completedBytes,
                    totalSize: totalSize,
                    reporter: reporter
                )
            )
            completedBytes += artifact.size
        }
        reporter.report(1)
    }

    private func prepareRepositoryDirectory(_ repositoryDirectory: URL) throws {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: repositoryDirectory.path)
            if attributes[.type] as? FileAttributeType != .typeDirectory {
                try removeIfPresent(repositoryDirectory)
            }
        } catch where VoiceInputModelFileError.isNoSuchFile(error) {
            // The normal first-install path creates the directory below.
        }
        try fileManager.createDirectory(at: repositoryDirectory, withIntermediateDirectories: true)
    }

    static func artifactURL(
        baseURL: URL? = nil,
        repository: String,
        revision: String,
        path: String
    ) -> URL {
        let components = repository.split(separator: "/") + ["resolve", Substring(revision)] + path.split(separator: "/")
        return components.reduce(baseURL ?? makeDefaultBaseURL()) { partial, component in
            partial.appendingPathComponent(String(component), isDirectory: false)
        }
    }

    private func download(
        _ artifact: VoiceInputModelArtifact,
        context: ArtifactDownloadContext
    ) async throws {
        let partialURL = context.finalURL.appendingPathExtension("part")
        try fileManager.createDirectory(
            at: context.finalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try normalizePartial(at: partialURL, expectedSize: artifact.size)

        var attempt = 0
        while attempt < 4 {
            try Task.checkCancellation()
            if try recoverCompletedPartial(
                artifact,
                at: partialURL,
                finalURL: context.finalURL
            ) {
                return
            }
            let existingBytes = try fileSize(at: partialURL) ?? 0
            do {
                if try await performDownloadAttempt(
                    artifact,
                    context: context,
                    partialURL: partialURL,
                    existingBytes: existingBytes
                ) {
                    return
                }
                // A stale byte range is local resume state, not a failed
                // network retry. Retry the same attempt from an empty part.
                continue
            } catch let error where VoiceInputModelFileError.isCancellation(error) {
                throw CancellationError()
            } catch {
                if try recoverCompletedPartial(
                    artifact,
                    at: partialURL,
                    finalURL: context.finalURL
                ) {
                    return
                }
                guard attempt < 3, Self.isTransient(error) else {
                    if error is VoiceInputArtifactSizeError ||
                        error is VoiceInputArtifactOversizeError ||
                        error is VoiceInputInvalidContentRangeError {
                        try removeIfPresent(partialURL)
                    }
                    throw error
                }
                let delay = Self.retryDelay(for: error) ?? pow(2, Double(attempt)) * 0.5
                try await retrySleeper.sleep(seconds: delay)
                attempt += 1
            }
        }
    }

    private func performDownloadAttempt(
        _ artifact: VoiceInputModelArtifact,
        context: ArtifactDownloadContext,
        partialURL: URL,
        existingBytes: Int64
    ) async throws -> Bool {
        let result = try await httpDownloader.download(
            request: request(for: artifact, descriptor: context.descriptor, existingBytes: existingBytes),
            to: partialURL,
            expectedSize: artifact.size,
            existingBytes: existingBytes
        ) { artifactBytes in
            let aggregate = context.completedBytes + min(artifact.size, max(0, artifactBytes))
            context.reporter.report(Double(aggregate) / Double(context.totalSize))
        }
        if result.statusCode == 416, existingBytes > 0 {
            try removeIfPresent(partialURL)
            return false
        }
        try validateHTTPResult(result, partialURL: partialURL)
        try validateDownloadedArtifact(
            artifact,
            partialURL: partialURL,
            finalURL: context.finalURL
        )
        return true
    }

    private func request(
        for artifact: VoiceInputModelArtifact,
        descriptor: VoiceInputPinnedModelDescriptor,
        existingBytes: Int64
    ) -> URLRequest {
        var request = URLRequest(
            url: Self.artifactURL(
                baseURL: baseURL,
                repository: descriptor.repository,
                revision: descriptor.revision,
                path: artifact.path
            )
        )
        request.timeoutInterval = 120
        if existingBytes > 0 {
            request.setValue("bytes=\(existingBytes)-", forHTTPHeaderField: "Range")
        }
        return request
    }

    private func validateHTTPResult(
        _ result: VoiceInputHTTPDownloadResult,
        partialURL: URL
    ) throws {
        guard result.statusCode == 200 || result.statusCode == 206 else {
            throw VoiceInputHTTPStatusError(
                statusCode: result.statusCode,
                retryAfter: Self.retryDelay(from: result.headers["retry-after"])
            )
        }
        guard result.finalURL?.scheme?.lowercased() == "https" else {
            try removeIfPresent(partialURL)
            throw VoiceInputServiceError.modelDownload("The model download redirected to an insecure URL.")
        }
    }

    private func validateDownloadedArtifact(
        _ artifact: VoiceInputModelArtifact,
        partialURL: URL,
        finalURL: URL
    ) throws {
        let size = try fileSize(at: partialURL) ?? 0
        if size < artifact.size {
            throw VoiceInputArtifactSizeError()
        }
        guard size == artifact.size else {
            try removeIfPresent(partialURL)
            throw VoiceInputServiceError.modelDownload("A voice model artifact has an unexpected size.")
        }
        guard try VoiceInputModelArtifactIntegrity.contentHash(of: partialURL, artifact: artifact) else {
            try removeIfPresent(partialURL)
            try removeIfPresent(finalURL)
            throw VoiceInputServiceError.modelDownload("A voice model artifact failed integrity validation.")
        }
        try removeIfPresent(finalURL)
        try fileManager.moveItem(at: partialURL, to: finalURL)
    }

    private func validatedCompletedBytes(
        artifacts: [VoiceInputModelArtifact],
        repositoryDirectory: URL
    ) throws -> Int64 {
        try artifacts.reduce(0) { total, artifact in
            let url = repositoryDirectory.appendingPathComponent(artifact.path)
            return total + (try completedArtifactIsValid(artifact, at: url) ? artifact.size : 0)
        }
    }

    private func completedArtifactIsValid(_ artifact: VoiceInputModelArtifact, at url: URL) throws -> Bool {
        guard let size = try fileSize(at: url) else { return false }
        guard size == artifact.size,
              try VoiceInputModelArtifactIntegrity.contentHash(of: url, artifact: artifact) else {
            try removeIfPresent(url)
            return false
        }
        return true
    }

    private func normalizePartial(at url: URL, expectedSize: Int64) throws {
        guard let size = try fileSize(at: url) else { return }
        if size <= 0 || size > expectedSize {
            try removeIfPresent(url)
        }
    }

    private func recoverCompletedPartial(
        _ artifact: VoiceInputModelArtifact,
        at partialURL: URL,
        finalURL: URL
    ) throws -> Bool {
        guard try fileSize(at: partialURL) == artifact.size else { return false }
        guard try VoiceInputModelArtifactIntegrity.contentHash(of: partialURL, artifact: artifact) else {
            try removeIfPresent(partialURL)
            return false
        }
        try removeIfPresent(finalURL)
        try fileManager.moveItem(at: partialURL, to: finalURL)
        return true
    }

    private func removeUnexpectedEntries(
        in repositoryDirectory: URL,
        artifacts: [VoiceInputModelArtifact]
    ) throws {
        guard let enumerator = fileManager.enumerator(
            at: repositoryDirectory,
            includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
            options: []
        ) else {
            throw VoiceInputServiceError.modelCache("Could not enumerate staged voice model artifacts.")
        }
        let allowedFiles = Set(artifacts.flatMap { [$0.path, "\($0.path).part"] })
        let allowedDirectories = VoiceInputModelArtifactInventory.expectedDirectoryPaths(for: artifacts)
        let rootPath = repositoryDirectory.standardizedFileURL.path
        var removals: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey])
            let path = url.standardizedFileURL.path
            guard path.hasPrefix("\(rootPath)/") else {
                enumerator.skipDescendants()
                removals.append(url)
                continue
            }
            let relativePath = String(path.dropFirst(rootPath.count + 1))
            if values.isSymbolicLink == true {
                enumerator.skipDescendants()
                removals.append(url)
                continue
            }
            if values.isDirectory == true {
                guard allowedDirectories.contains(relativePath) else {
                    enumerator.skipDescendants()
                    removals.append(url)
                    continue
                }
            } else if values.isRegularFile == true {
                if !allowedFiles.contains(relativePath) {
                    removals.append(url)
                }
            } else {
                enumerator.skipDescendants()
                removals.append(url)
            }
        }
        for url in removals.sorted(by: { $0.path.count > $1.path.count }) {
            try removeIfPresent(url)
        }
    }

    private func fileSize(at url: URL) throws -> Int64? {
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = (attributes[.size] as? NSNumber)?.int64Value else {
                try removeIfPresent(url)
                return nil
            }
            return size
        } catch {
            let nsError = error as NSError
            if (nsError.domain == NSCocoaErrorDomain &&
                nsError.code == CocoaError.Code.fileReadNoSuchFile.rawValue) ||
                (nsError.domain == NSPOSIXErrorDomain && nsError.code == POSIXErrorCode.ENOENT.rawValue) {
                return nil
            }
            throw error
        }
    }

    private func removeIfPresent(_ url: URL) throws {
        try VoiceInputModelFileError.removeIfPresent(url, fileManager: fileManager)
    }

    private static func isTransient(_ error: Error) -> Bool {
        if error is VoiceInputArtifactSizeError {
            return true
        }
        if error is VoiceInputHTTPStatusError {
            let statusCode = (error as? VoiceInputHTTPStatusError)?.statusCode ?? 0
            return statusCode == 408 || statusCode == 429 || (500...599).contains(statusCode)
        }
        guard let urlError = error as? URLError else { return false }
        return transientURLErrorCodes.contains(urlError.code)
    }

    private static func retryDelay(for error: Error) -> TimeInterval? {
        (error as? VoiceInputHTTPStatusError)?.retryAfter
    }

    private static func retryDelay(from value: String?) -> TimeInterval? {
        guard let value else { return nil }
        if let seconds = TimeInterval(value), seconds >= 0 {
            return seconds
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        guard let date = formatter.date(from: value) else { return nil }
        return max(0, date.timeIntervalSinceNow)
    }

    private static let transientURLErrorCodes: Set<URLError.Code> = [
        .cannotConnectToHost,
        .cannotFindHost,
        .dataNotAllowed,
        .dnsLookupFailed,
        .internationalRoamingOff,
        .networkConnectionLost,
        .notConnectedToInternet,
        .resourceUnavailable,
        .timedOut
    ]

    private static func makeDefaultBaseURL() -> URL {
        guard let url = URL(string: "https://huggingface.co") else {
            preconditionFailure("The static Hugging Face base URL is invalid.")
        }
        return url
    }
}

private struct VoiceInputHTTPStatusError: LocalizedError {
    let statusCode: Int
    let retryAfter: TimeInterval?

    var errorDescription: String? {
        "Hugging Face returned HTTP \(statusCode)."
    }
}

private struct VoiceInputArtifactSizeError: LocalizedError {
    var errorDescription: String? {
        "A voice model artifact was incomplete."
    }
}

struct VoiceInputArtifactOversizeError: LocalizedError {
    var errorDescription: String? {
        "A voice model artifact exceeded its pinned size."
    }
}

struct VoiceInputInvalidContentRangeError: LocalizedError {
    var errorDescription: String? {
        "Hugging Face returned an invalid byte range."
    }
}

private struct ArtifactDownloadContext {
    let descriptor: VoiceInputPinnedModelDescriptor
    let finalURL: URL
    let completedBytes: Int64
    let totalSize: Int64
    let reporter: CoalescingVoiceInputDownloadProgress
}
