import Foundation
import XCTest

@testable import Alveary

/// Records every request the fetcher issues and replays canned responses, so the URL shapes and the
/// size gate can be asserted without touching the network.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Stub: Sendable {
        let statusCode: Int
        let headers: [String: String]
        let body: Data

        init(statusCode: Int = 200, headers: [String: String] = [:], body: Data = Data()) {
            self.statusCode = statusCode
            self.headers = headers
            self.body = body
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responder: (@Sendable (URLRequest) -> Stub)?
    nonisolated(unsafe) private static var recorded: [URLRequest] = []

    static func setResponder(_ responder: (@Sendable (URLRequest) -> Stub)?) {
        lock.lock()
        defer { lock.unlock() }
        Self.responder = responder
        recorded = []
    }

    static var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    /// A session wired to this protocol. `bytes(for:)` reads through it like any other transport.
    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return URLSession(configuration: configuration)
    }

    override static func canInit(with request: URLRequest) -> Bool { true }
    override static func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        // `httpBody` is stripped from the request the protocol sees, so restore it from the stream
        // before recording — the batch test asserts on the JSON payload.
        var recordedRequest = request
        if recordedRequest.httpBody == nil, let stream = request.httpBodyStream {
            recordedRequest.httpBody = Self.drain(stream)
        }
        Self.recorded.append(recordedRequest)
        let stub = Self.responder?(recordedRequest) ?? Stub()
        Self.lock.unlock()

        let response = HTTPURLResponse(
            url: request.url ?? URL(fileURLWithPath: "/"),
            statusCode: stub.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: stub.headers
        )
        if let response {
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        }
        if !stub.body.isEmpty {
            client?.urlProtocol(self, didLoad: stub.body)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}

    private static func drain(_ stream: InputStream) -> Data {
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        var buffer = [UInt8](repeating: 0, count: bufferSize)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: bufferSize)
            if read <= 0 {
                break
            }
            data.append(contentsOf: buffer[0..<read])
        }
        return data
    }
}

/// A one-pixel PNG, so a decode downstream of the fetcher would succeed if a test wanted one.
let stubImageBytes = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

func makeTokenShellRunner(token: String = "gho_test") -> MockShellRunner {
    MockShellRunner(
        defaultResponse: .success(
            ShellResult(stdout: token + "\n", stderr: "", exitCode: 0, stdoutWasTruncated: false, stderrWasTruncated: false)
        )
    )
}

func makeDiffImageBlobFetcher(shell: MockShellRunner) -> GitHubDiffImageBlobFetcher {
    GitHubDiffImageBlobFetcher(
        shellRunner: shell,
        executableResolver: PullRequestsExecutablePathResolverFake(path: "/opt/homebrew/bin/gh"),
        session: StubURLProtocol.makeSession()
    )
}

func gitHubBlobSource(
    path: String = "assets/logo.png",
    storage: GitHubImageBlobSource.Storage
) -> DiffImageBlobSource {
    .gitHub(GitHubImageBlobSource(owner: "octo", repo: "demo", path: path, storage: storage))
}
