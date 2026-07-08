import CryptoKit
import Foundation

struct GitHubCLIAppUpdateDownloader: AppUpdateDownloading, @unchecked Sendable {
    private static let downloadTimeout: TimeInterval = 600

    private let shellRunner: any ShellRunner
    private let executableResolver: any ExecutablePathResolving
    private let fileManager: FileManager
    private let temporaryDirectory: URL
    private let sessionConfiguration: URLSessionConfiguration

    init(
        shellRunner: any ShellRunner = DefaultShellRunner(),
        executableResolver: (any ExecutablePathResolving)? = nil,
        fileManager: FileManager = .default,
        temporaryDirectory: URL = FileManager.default.temporaryDirectory,
        sessionConfiguration: URLSessionConfiguration = .ephemeral
    ) {
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver ?? DefaultExecutablePathResolver(shell: shellRunner)
        self.fileManager = fileManager
        self.temporaryDirectory = temporaryDirectory
        self.sessionConfiguration = sessionConfiguration
    }

    func download(
        release: AppUpdateRelease,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL {
        let token = try await authenticationToken()
        let downloadDirectory = temporaryDirectory
            .appendingPathComponent("AlvearyUpdates", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try fileManager.createDirectory(
            at: downloadDirectory,
            withIntermediateDirectories: true
        )

        let zipURL = downloadDirectory.appendingPathComponent(release.asset.name)
        do {
            await progress(0)
            let request = authenticatedAssetRequest(
                url: release.asset.apiURL,
                token: token
            )
            try await downloadAsset(
                request: request,
                destinationURL: zipURL,
                expectedSize: release.asset.size,
                progress: progress
            )
            try verifyDownloadedSize(
                zipURL: zipURL,
                expectedSize: release.asset.size
            )
            try verifyDownloadedDigest(
                zipURL: zipURL,
                expectedDigest: release.asset.digest
            )
            await progress(1)
            return zipURL
        } catch {
            try? fileManager.removeItem(at: downloadDirectory)
            throw error
        }
    }
}

private extension GitHubCLIAppUpdateDownloader {
    func authenticationToken() async throws -> String {
        guard let ghExecutable = await executableResolver.resolveExecutablePath(for: "gh") else {
            throw AppUpdateFailure(message: "GitHub CLI is not installed.")
        }

        let result = try await shellRunner.run(
            executable: ghExecutable,
            args: ["auth", "token"],
            timeout: .seconds(5),
            stdoutLimitBytes: 64 * 1024,
            stderrLimitBytes: 64 * 1024
        )

        guard result.succeeded else {
            throw AppUpdateFailure(message: Self.failureMessage(from: result))
        }

        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw AppUpdateFailure(message: "GitHub CLI did not return an authentication token.")
        }
        return token
    }

    func authenticatedAssetRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = Self.downloadTimeout
        request.setValue("application/octet-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("Alveary", forHTTPHeaderField: "User-Agent")
        return request
    }

    func downloadAsset(
        request: URLRequest,
        destinationURL: URL,
        expectedSize: Int?,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws {
        let delegate = GitHubAssetDataDownloadDelegate(
            destinationURL: destinationURL,
            expectedSize: expectedSize,
            fileManager: fileManager,
            progress: progress
        )
        let session = URLSession(
            configuration: sessionConfiguration,
            delegate: delegate,
            delegateQueue: nil
        )
        let task = session.dataTask(with: request)

        defer {
            session.invalidateAndCancel()
        }

        do {
            try await withTaskCancellationHandler {
                try await delegate.download(with: task)
            } onCancel: {
                task.cancel()
                session.invalidateAndCancel()
            }
            await delegate.waitForProgressReports()
        } catch {
            await delegate.waitForProgressReports()
            throw error
        }
    }

    func verifyDownloadedSize(zipURL: URL, expectedSize: Int?) throws {
        guard let expectedSize else {
            return
        }

        let attributes = try fileManager.attributesOfItem(atPath: zipURL.path)
        let downloadedByteCount = (attributes[.size] as? NSNumber)?.intValue
        guard downloadedByteCount == expectedSize else {
            throw AppUpdateFailure(
                message: "Downloaded \(downloadedByteCount ?? 0) bytes, but GitHub reported \(expectedSize) bytes."
            )
        }
    }

    func verifyDownloadedDigest(
        zipURL: URL,
        expectedDigest: AppUpdateReleaseAssetDigest
    ) throws {
        let actualDigest = try sha256HexDigest(for: zipURL)
        guard actualDigest == expectedDigest.sha256HexDigest else {
            throw AppUpdateFailure(message: "Downloaded update failed SHA-256 verification.")
        }
    }

    func sha256HexDigest(for url: URL) throws -> String {
        let fileHandle = try FileHandle(forReadingFrom: url)
        defer {
            try? fileHandle.close()
        }

        var hasher = SHA256()
        while let data = try fileHandle.read(upToCount: 1024 * 1024),
              !data.isEmpty {
            hasher.update(data: data)
        }

        return hasher.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }

    static func failureMessage(from result: ShellResult) -> String {
        if result.exitCode == 127 {
            return "GitHub CLI is not installed."
        }

        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = stderr.isEmpty ? stdout : stderr
        guard !detail.isEmpty else {
            return "GitHub CLI failed to provide an authentication token."
        }
        if detail.localizedCaseInsensitiveContains("not logged") || detail.localizedCaseInsensitiveContains("authentication") {
            return "GitHub CLI is not authenticated."
        }
        return "GitHub CLI failed to provide an authentication token: \(detail)"
    }
}

private final class GitHubAssetDataDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let destinationURL: URL
    private let expectedSize: Int?
    private let fileManager: FileManager
    private let progress: @Sendable (Double) async -> Void
    private let lock = NSLock()

    private var continuation: CheckedContinuation<Void, any Error>?
    private var storedError: (any Error)?
    private var fileHandle: FileHandle?
    private var receivedByteCount: Int64 = 0
    private var responseExpectedByteCount: Int64 = 0
    private var didCreateDownloadedFile = false
    private var didResume = false
    private var lastReportedProgress = 0.0
    private var progressReports: [Task<Void, Never>] = []

    init(
        destinationURL: URL,
        expectedSize: Int?,
        fileManager: FileManager,
        progress: @escaping @Sendable (Double) async -> Void
    ) {
        self.destinationURL = destinationURL
        self.expectedSize = expectedSize
        self.fileManager = fileManager
        self.progress = progress
    }

    func download(with task: URLSessionDataTask) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            self.continuation = continuation
            lock.unlock()
            task.resume()
        }
    }

    func waitForProgressReports() async {
        let reports: [Task<Void, Never>] = lock.withLock {
            progressReports
        }

        for report in reports {
            await report.value
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        if let error = httpError(from: response) {
            lock.withLock {
                storedError = error
            }
            completionHandler(.cancel)
            return
        }

        do {
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            guard fileManager.createFile(atPath: destinationURL.path, contents: nil) else {
                throw AppUpdateFailure(message: "Alveary could not create the update download file.")
            }
            let handle = try FileHandle(forWritingTo: destinationURL)
            lock.withLock {
                fileHandle = handle
                responseExpectedByteCount = response.expectedContentLength
                didCreateDownloadedFile = true
            }
            completionHandler(.allow)
        } catch {
            lock.withLock {
                storedError = error
            }
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        let progressValue: Double?
        do {
            progressValue = try lock.withLock {
                guard let fileHandle else {
                    throw AppUpdateFailure(message: "Alveary could not write the update download.")
                }
                try fileHandle.write(contentsOf: data)
                receivedByteCount += Int64(data.count)
                let expectedByteCount = expectedDownloadByteCount()
                guard expectedByteCount > 0 else {
                    return nil
                }
                return min(max(Double(receivedByteCount) / Double(expectedByteCount), 0), 1)
            }
        } catch {
            lock.withLock {
                storedError = error
            }
            dataTask.cancel()
            return
        }

        if let progressValue {
            reportProgressIfNeeded(progressValue)
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        var redirectedRequest = request
        redirectedRequest.cachePolicy = .reloadIgnoringLocalCacheData
        redirectedRequest.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        redirectedRequest.setValue("no-cache", forHTTPHeaderField: "Pragma")
        if task.originalRequest?.url?.host != request.url?.host {
            redirectedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        }
        completionHandler(redirectedRequest)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Error)?
    ) {
        closeFileHandle()
        let state = lock.withLock {
            (storedError: storedError, didCreateDownloadedFile: didCreateDownloadedFile)
        }
        let completionError = state.storedError ?? normalizedCompletionError(error) ?? httpError(from: task.response)
        if completionError != nil {
            try? fileManager.removeItem(at: destinationURL)
        }

        if completionError == nil && !state.didCreateDownloadedFile {
            resume(
                throwing: AppUpdateFailure(message: "GitHub did not download the update asset.")
            )
            return
        }

        if let completionError {
            resume(throwing: completionError)
        } else {
            resumeReturningSuccess()
        }
    }

    private func expectedDownloadByteCount() -> Int64 {
        if let expectedSize, expectedSize > 0 {
            return Int64(expectedSize)
        }
        return responseExpectedByteCount > 0 ? responseExpectedByteCount : 0
    }

    private func reportProgressIfNeeded(_ progressValue: Double) {
        lock.lock()
        let shouldReport = progressValue >= 1 || progressValue - lastReportedProgress >= 0.01
        guard shouldReport else {
            lock.unlock()
            return
        }

        lastReportedProgress = progressValue
        let report = Task { [progress] in
            await progress(progressValue)
        }
        progressReports.append(report)
        lock.unlock()
    }

    private func httpError(from response: URLResponse?) -> (any Error)? {
        guard let response = response as? HTTPURLResponse,
              !(200..<300).contains(response.statusCode) else {
            return nil
        }
        return AppUpdateFailure(message: "GitHub failed to download the update asset. (HTTP \(response.statusCode))")
    }

    private func normalizedCompletionError(_ error: (any Error)?) -> (any Error)? {
        if let urlError = error as? URLError,
           urlError.code == .cancelled {
            return CancellationError()
        }
        return error
    }

    private func closeFileHandle() {
        let handle: FileHandle? = lock.withLock {
            let handle = fileHandle
            fileHandle = nil
            return handle
        }
        try? handle?.close()
    }

    private func resumeReturningSuccess() {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }

        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume()
    }

    private func resume(throwing error: any Error) {
        lock.lock()
        guard !didResume, let continuation else {
            lock.unlock()
            return
        }

        didResume = true
        self.continuation = nil
        lock.unlock()
        continuation.resume(throwing: error)
    }
}

private extension NSLock {
    func withLock<Result>(_ body: () throws -> Result) rethrows -> Result {
        lock()
        defer { unlock() }
        return try body()
    }
}

private extension String {
    func localizedCaseInsensitiveContains(_ other: String) -> Bool {
        range(of: other, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }
}
