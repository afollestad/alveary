import Foundation

struct URLSessionVoiceInputHTTPDownloader: VoiceInputHTTPDownloading {
    func download(
        request: URLRequest,
        to partialURL: URL,
        expectedSize: Int64,
        existingBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) async throws -> VoiceInputHTTPDownloadResult {
        let delegate = VoiceInputStreamingDownloadDelegate(
            request: request,
            partialURL: partialURL,
            expectedSize: expectedSize,
            existingBytes: existingBytes,
            progress: progress
        )
        return try await delegate.start()
    }
}

final class VoiceInputStreamingDownloadDelegate: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let request: URLRequest
    private let partialURL: URL
    private let expectedSize: Int64
    private let existingBytes: Int64
    private let progress: @Sendable (Int64) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<VoiceInputHTTPDownloadResult, Error>?
    private var task: URLSessionDataTask?
    private var session: URLSession?
    private var response: HTTPURLResponse?
    private var fileHandle: FileHandle?
    private var bytesWritten: Int64 = 0
    private var terminalError: Error?

    init(
        request: URLRequest,
        partialURL: URL,
        expectedSize: Int64,
        existingBytes: Int64,
        progress: @escaping @Sendable (Int64) -> Void
    ) {
        self.request = request
        self.partialURL = partialURL
        self.expectedSize = expectedSize
        self.existingBytes = existingBytes
        self.progress = progress
    }

    func start() async throws -> VoiceInputHTTPDownloadResult {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.withLock {
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.continuation = continuation
                    let queue = OperationQueue()
                    queue.maxConcurrentOperationCount = 1
                    let session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: queue)
                    self.session = session
                    let task = session.dataTask(with: request)
                    self.task = task
                    task.resume()
                }
            }
        } onCancel: {
            self.lock.withLock { self.task?.cancel() }
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            terminalError = VoiceInputServiceError.modelDownload("Hugging Face returned a non-HTTP response.")
            completionHandler(.cancel)
            return
        }
        self.response = response
        guard response.statusCode == 200 || response.statusCode == 206 else {
            completionHandler(.cancel)
            return
        }

        do {
            let append = response.statusCode == 206
            if append {
                guard VoiceInputHTTPContentRange.isValid(
                    response.value(forHTTPHeaderField: "Content-Range"),
                    matchesStart: existingBytes,
                    total: expectedSize
                ) else {
                    throw VoiceInputInvalidContentRangeError()
                }
            }
            fileHandle = try Self.openFile(
                at: partialURL,
                append: append,
                expectedExistingBytes: existingBytes
            )
            bytesWritten = append ? existingBytes : 0
            progress(bytesWritten)
            completionHandler(.allow)
        } catch {
            terminalError = error
            completionHandler(.cancel)
        }
    }

    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        do {
            let (nextByteCount, overflow) = bytesWritten.addingReportingOverflow(Int64(data.count))
            guard !overflow, nextByteCount <= expectedSize else {
                throw VoiceInputArtifactOversizeError()
            }
            try fileHandle?.write(contentsOf: data)
            bytesWritten = nextByteCount
            progress(bytesWritten)
        } catch {
            terminalError = error
            dataTask.cancel()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        do {
            try fileHandle?.close()
        } catch {
            terminalError = terminalError ?? error
        }
        fileHandle = nil

        let completion = lock.withLock { () -> CheckedContinuation<VoiceInputHTTPDownloadResult, Error>? in
            defer {
                continuation = nil
                self.task = nil
                self.session = nil
            }
            return continuation
        }
        session.finishTasksAndInvalidate()
        guard let completion else { return }
        resume(completion, error: error)
    }

    private func resume(
        _ completion: CheckedContinuation<VoiceInputHTTPDownloadResult, Error>,
        error: Error?
    ) {
        if let terminalError {
            completion.resume(throwing: terminalError)
        } else if let response, response.statusCode != 200, response.statusCode != 206 {
            completion.resume(returning: Self.result(from: response))
        } else if let error {
            completion.resume(throwing: error)
        } else if let response {
            completion.resume(returning: Self.result(from: response))
        } else {
            completion.resume(throwing: VoiceInputServiceError.modelDownload("The model download returned no response."))
        }
    }

    private static func result(from response: HTTPURLResponse) -> VoiceInputHTTPDownloadResult {
        let headers = response.allHeaderFields.reduce(into: [String: String]()) { result, entry in
            guard let key = entry.key as? String, let value = entry.value as? String else { return }
            result[key.lowercased()] = value
        }
        return VoiceInputHTTPDownloadResult(
            statusCode: response.statusCode,
            headers: headers,
            finalURL: response.url
        )
    }

    private static func openFile(
        at url: URL,
        append: Bool,
        expectedExistingBytes: Int64
    ) throws -> FileHandle {
        if !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        if append {
            let offset = try handle.seekToEnd()
            guard offset == UInt64(expectedExistingBytes) else {
                try handle.close()
                throw VoiceInputServiceError.modelDownload("The resumable model artifact changed on disk.")
            }
        } else {
            try handle.truncate(atOffset: 0)
            try handle.seek(toOffset: 0)
        }
        return handle
    }

}

enum VoiceInputHTTPContentRange {
    static func isValid(_ value: String?, matchesStart start: Int64, total: Int64) -> Bool {
        guard let value,
              value.hasPrefix("bytes "),
              let slash = value.lastIndex(of: "/"),
              Int64(value[value.index(after: slash)...]) == total else {
            return false
        }
        let rangeStart = value.index(value.startIndex, offsetBy: 6)
        let range = value[rangeStart..<slash]
        guard let dash = range.firstIndex(of: "-"),
              Int64(range[..<dash]) == start,
              let end = Int64(range[range.index(after: dash)...]) else {
            return false
        }
        return end >= start && end < total
    }
}
