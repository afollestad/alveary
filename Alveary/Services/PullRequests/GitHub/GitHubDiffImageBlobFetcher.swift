import Foundation

/// Fetches pull request image bytes straight from GitHub, because a pull request diff has no
/// checkout behind it to read them from.
///
/// **This deliberately does not route through `gh api`.** `gh` attaches its `Authorization` header
/// only to `api.github.com`; against `raw.githubusercontent.com`, `media.githubusercontent.com`, and
/// the LFS batch endpoint it sends none, so public repositories appear to work while every private
/// one 404s. Setting the header here is the whole reason this type owns a `URLSession` instead.
/// The token still comes from `gh auth token`, so there is no second credential to manage.
final class GitHubDiffImageBlobFetcher: DiffImageBlobFetching {
    private let tokenStore: GitHubImageBlobTokenStore
    private let session: URLSession
    private let requestTimeout: TimeInterval

    init(
        shellRunner: ShellRunner,
        executableResolver: ExecutablePathResolving,
        session: URLSession = .shared,
        requestTimeout: TimeInterval = 60
    ) {
        tokenStore = GitHubImageBlobTokenStore(
            shellRunner: shellRunner,
            executableResolver: executableResolver
        )
        self.session = session
        self.requestTimeout = requestTimeout
    }

    func blob(for source: DiffImageBlobSource, maxBytes: Int) async throws -> Data {
        guard case .gitHub(let gitHubSource) = source else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }

        switch gitHubSource.storage {
        case .blob(let ref):
            return try await rawBlob(source: gitHubSource, ref: ref, maxBytes: maxBytes)
        case .lfs(let oid, let byteSize):
            // The pointer already told us the size, so an oversized object costs no request at all.
            guard byteSize <= maxBytes else {
                throw DiffImageBlobTooLargeError(byteSize: byteSize)
            }
            return try await lfsObject(source: gitHubSource, oid: oid, byteSize: byteSize, maxBytes: maxBytes)
        }
    }

    /// Always nil: remote bytes never already sit on disk, so opening one always materializes a
    /// temp file through the preview loader's disk cache.
    func existingFileURL(for source: DiffImageBlobSource) -> URL? {
        nil
    }
}

// MARK: - Transports

private extension GitHubDiffImageBlobFetcher {
    func rawBlob(source: GitHubImageBlobSource, ref: String, maxBytes: Int) async throws -> Data {
        guard let url = Self.rawURL(owner: source.owner, repo: source.repo, ref: ref, path: source.path) else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }

        return try await authenticatedRetryingOnExpiredToken { token in
            var request = URLRequest(url: url)
            request.timeoutInterval = self.requestTimeout
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("Alveary", forHTTPHeaderField: "User-Agent")
            return try await self.boundedDownload(request: request, maxBytes: maxBytes)
        }
    }

    func lfsObject(
        source: GitHubImageBlobSource,
        oid: String,
        byteSize: Int,
        maxBytes: Int
    ) async throws -> Data {
        let href = try await authenticatedRetryingOnExpiredToken { token in
            try await self.resolveLFSDownloadHref(
                source: source,
                oid: oid,
                byteSize: byteSize,
                token: token
            )
        }

        // The batch endpoint hands back a pre-signed URL; sending our token to it is unnecessary and
        // some storage backends reject a request carrying both.
        var request = URLRequest(url: href)
        request.timeoutInterval = requestTimeout
        request.setValue("Alveary", forHTTPHeaderField: "User-Agent")
        return try await boundedDownload(request: request, maxBytes: maxBytes)
    }

    func resolveLFSDownloadHref(
        source: GitHubImageBlobSource,
        oid: String,
        byteSize: Int,
        token: String
    ) async throws -> URL {
        guard let batchURL = Self.lfsBatchURL(owner: source.owner, repo: source.repo) else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }

        var request = URLRequest(url: batchURL)
        request.httpMethod = "POST"
        request.timeoutInterval = requestTimeout
        request.setValue("application/vnd.git-lfs+json", forHTTPHeaderField: "Accept")
        request.setValue("application/vnd.git-lfs+json", forHTTPHeaderField: "Content-Type")
        request.setValue("Alveary", forHTTPHeaderField: "User-Agent")
        // The LFS protocol authenticates with basic auth, not a bearer token.
        let credentials = Data("x-access-token:\(token)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(
            LFSBatchRequest(
                operation: "download",
                transfers: ["basic"],
                objects: [LFSBatchRequest.Object(oid: oid, size: byteSize)]
            )
        )

        let (data, response) = try await session.data(for: request)
        try Self.validate(response: response)

        let decoded = try JSONDecoder().decode(LFSBatchResponse.self, from: data)
        guard let object = decoded.objects.first else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }
        if let error = object.error {
            throw GitHubDiffImageBlobFetcherError.lfsObjectUnavailable(message: error.message)
        }
        guard let href = object.actions?.download?.href,
              let url = URL(string: href) else {
            throw DiffImagePreviewLoaderError.unsupportedSource
        }
        return url
    }

    /// Reads the body in one bulk load, bounded by asking for at most `maxBytes + 1` bytes.
    ///
    /// The bound is a `Range` header rather than a streamed byte count on purpose: iterating
    /// `URLSession.AsyncBytes` yields one `UInt8` per `await`, which measured **70s for 10MB**
    /// against 4ms for `data(for:)` — it would have frozen a slot for over a minute on exactly the
    /// large images Git LFS exists to hold. Requesting one byte past the limit is what still lets an
    /// oversized blob be detected without transferring it, and `Content-Range` names its true size.
    func boundedDownload(request: URLRequest, maxBytes: Int) async throws -> Data {
        var bounded = request
        bounded.setValue("bytes=0-\(maxBytes)", forHTTPHeaderField: "Range")

        let (data, response) = try await session.data(for: bounded)
        try Self.validate(response: response)
        try Task.checkCancellation()

        if let totalByteCount = Self.totalByteCount(from: response), totalByteCount > maxBytes {
            throw DiffImageBlobTooLargeError(byteSize: totalByteCount)
        }
        // Also covers a server that ignored the range and sent the whole body.
        guard data.count <= maxBytes else {
            throw DiffImageBlobTooLargeError(byteSize: nil)
        }
        return data
    }

    /// The resource's full size from a partial response's `Content-Range: bytes 0-1023/166854`.
    /// Nil when the server answered 200 with the whole body, where the length speaks for itself.
    static func totalByteCount(from response: URLResponse) -> Int? {
        guard let http = response as? HTTPURLResponse,
              let contentRange = http.value(forHTTPHeaderField: "Content-Range"),
              let total = contentRange.split(separator: "/").last,
              total != "*" else {
            return nil
        }
        return Int(total)
    }

    /// Runs `work` with a token, and retries once with a freshly minted one when GitHub rejects the
    /// cached token — a token can be rotated or re-scoped while the app is running.
    func authenticatedRetryingOnExpiredToken<Value>(
        _ work: (String) async throws -> Value
    ) async throws -> Value {
        let token = try await tokenStore.token()
        do {
            return try await work(token)
        } catch GitHubDiffImageBlobFetcherError.unauthorized {
            await tokenStore.invalidate()
            let refreshed = try await tokenStore.token()
            return try await work(refreshed)
        }
    }

    static func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else {
            return
        }
        switch http.statusCode {
        // 206 is the normal answer to `boundedDownload`'s range request.
        case 200..<300:
            return
        case 401, 403:
            throw GitHubDiffImageBlobFetcherError.unauthorized
        default:
            throw GitHubDiffImageBlobFetcherError.httpStatus(http.statusCode)
        }
    }
}

// MARK: - URLs

extension GitHubDiffImageBlobFetcher {
    /// Percent-encodes each path segment separately so a `/` in the diff path stays a separator
    /// while spaces and `#` inside a segment do not truncate the URL.
    static func encode(path: String) -> String? {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        var encoded: [String] = []
        for segment in segments {
            guard let component = segment.addingPercentEncoding(withAllowedCharacters: allowed) else {
                return nil
            }
            encoded.append(component)
        }
        return encoded.joined(separator: "/")
    }

    static func rawURL(owner: String, repo: String, ref: String, path: String) -> URL? {
        guard let encodedPath = encode(path: path),
              let encodedRef = ref.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) else {
            return nil
        }
        return URL(string: "https://raw.githubusercontent.com/\(owner)/\(repo)/\(encodedRef)/\(encodedPath)")
    }

    static func lfsBatchURL(owner: String, repo: String) -> URL? {
        URL(string: "https://github.com/\(owner)/\(repo).git/info/lfs/objects/batch")
    }
}

enum GitHubDiffImageBlobFetcherError: Error, LocalizedError, Equatable {
    case unauthorized
    case httpStatus(Int)
    case lfsObjectUnavailable(message: String)
    case missingGitHubCLI
    case tokenUnavailable(message: String)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "GitHub rejected the stored credentials for this image."
        case .httpStatus(let code):
            return "GitHub returned HTTP \(code) for this image."
        case .lfsObjectUnavailable(let message):
            return "Git LFS object unavailable: \(message)"
        case .missingGitHubCLI:
            return "GitHub CLI is not installed."
        case .tokenUnavailable(let message):
            return message
        }
    }
}

// MARK: - Token

/// Caches the `gh auth token` value for the process, deduplicating concurrent reads so a diff full
/// of images does not spawn one `gh` per slot.
private actor GitHubImageBlobTokenStore {
    private let shellRunner: ShellRunner
    private let executableResolver: ExecutablePathResolving
    private var cachedToken: String?
    private var pending: Task<String, Error>?

    init(shellRunner: ShellRunner, executableResolver: ExecutablePathResolving) {
        self.shellRunner = shellRunner
        self.executableResolver = executableResolver
    }

    func token() async throws -> String {
        if let cachedToken {
            return cachedToken
        }
        if let pending {
            return try await pending.value
        }

        let task = Task { [shellRunner, executableResolver] in
            try await Self.readToken(shellRunner: shellRunner, executableResolver: executableResolver)
        }
        pending = task
        defer { pending = nil }

        let token = try await task.value
        cachedToken = token
        return token
    }

    func invalidate() {
        cachedToken = nil
    }

    private static func readToken(
        shellRunner: ShellRunner,
        executableResolver: ExecutablePathResolving
    ) async throws -> String {
        guard let ghExecutable = await executableResolver.resolveExecutablePath(for: "gh") else {
            throw GitHubDiffImageBlobFetcherError.missingGitHubCLI
        }

        let result = try await shellRunner.run(
            executable: ghExecutable,
            args: ["auth", "token"],
            timeout: .seconds(5),
            stdoutLimitBytes: 64 * 1024,
            stderrLimitBytes: 64 * 1024,
            standardInput: .nullDevice
        )
        guard result.succeeded else {
            let message = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitHubDiffImageBlobFetcherError.tokenUnavailable(
                message: message.isEmpty ? "GitHub CLI could not provide an authentication token." : message
            )
        }

        let token = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw GitHubDiffImageBlobFetcherError.tokenUnavailable(
                message: "GitHub CLI did not return an authentication token."
            )
        }
        return token
    }
}

// MARK: - Batch wire format

private struct LFSBatchRequest: Encodable {
    struct Object: Encodable {
        let oid: String
        let size: Int
    }

    let operation: String
    let transfers: [String]
    let objects: [Object]
}

private struct LFSBatchResponse: Decodable {
    let objects: [LFSBatchResponseObject]
}

private struct LFSBatchResponseObject: Decodable {
    let actions: LFSBatchDownloadActions?
    let error: LFSBatchObjectError?
}

private struct LFSBatchDownloadActions: Decodable {
    let download: LFSBatchDownloadAction?
}

private struct LFSBatchDownloadAction: Decodable {
    let href: String
}

private struct LFSBatchObjectError: Decodable {
    let message: String
}
