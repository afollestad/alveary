import Foundation

@testable import Alveary

class ServiceURLProtocolStub: URLProtocol, @unchecked Sendable {
    struct StubResponse: Sendable {
        let statusCode: Int
        let chunks: [Data]
        let headers: [String: String]
        let chunkDelayNanoseconds: UInt64?

        init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            chunks = [data]
            self.headers = headers
            chunkDelayNanoseconds = nil
        }

        init(
            statusCode: Int,
            chunks: [Data],
            headers: [String: String] = [:],
            chunkDelayNanoseconds: UInt64? = nil
        ) {
            self.statusCode = statusCode
            self.chunks = chunks
            self.headers = headers
            self.chunkDelayNanoseconds = chunkDelayNanoseconds
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: [StubResponse]] = [:]
    nonisolated(unsafe) private static var requests: [String] = []
    nonisolated(unsafe) private static var urlRequests: [URLRequest] = []

    static func configure(responses: [String: [StubResponse]]) {
        lock.lock()
        self.responses = responses
        requests = []
        urlRequests = []
        lock.unlock()
    }

    static func reset() {
        configure(responses: [:])
    }

    static func recordedRequests() -> [String] {
        lock.lock()
        let snapshot = requests
        lock.unlock()
        return snapshot
    }

    static func recordedURLRequests() -> [URLRequest] {
        lock.lock()
        let snapshot = urlRequests
        lock.unlock()
        return snapshot
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ServiceURLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }

        let response = Self.dequeueResponse(for: request, url: url.absoluteString)
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )

        client?.urlProtocol(self, didReceive: httpResponse ?? URLResponse(), cacheStoragePolicy: .notAllowed)
        if let chunkDelayNanoseconds = response.chunkDelayNanoseconds {
            for (index, chunk) in response.chunks.enumerated() {
                client?.urlProtocol(self, didLoad: chunk)
                if index + 1 < response.chunks.count {
                    Thread.sleep(forTimeInterval: Double(chunkDelayNanoseconds) / 1_000_000_000)
                }
            }
            client?.urlProtocolDidFinishLoading(self)
        } else {
            for chunk in response.chunks {
                client?.urlProtocol(self, didLoad: chunk)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private extension ServiceURLProtocolStub {
    static func dequeueResponse(for request: URLRequest, url: String) -> StubResponse {
        lock.lock()
        requests.append(url)
        urlRequests.append(request)
        defer { lock.unlock() }

        guard var queuedResponses = responses[url], !queuedResponses.isEmpty else {
            return StubResponse(statusCode: 404, data: Data())
        }

        let response = queuedResponses.removeFirst()
        responses[url] = queuedResponses
        return response
    }
}

struct ServiceTestAgentRegistry: AgentRegistry {
    let agents: [AgentDefinition]

    func agent(for id: String) -> AgentDefinition? {
        agents.first { $0.id == id }
    }
}

actor MCPTestProviderDetectionService: ProviderDetectionService {
    private var statuses: [String: ProviderStatus]
    private var paths: [String: String]
    private var checkAllCountValue = 0

    init(statuses: [String: ProviderStatus], paths: [String: String] = [:]) {
        self.statuses = statuses
        self.paths = paths
    }

    func resolvedPath(for providerId: String) -> String? {
        paths[providerId]
    }

    func status(for providerId: String) -> ProviderStatus {
        statuses[providerId] ?? .unchecked
    }

    func checkAllProviders() async {
        checkAllCountValue += 1
    }

    func checkProvider(_ providerId: String) async {}

    func checkAllCount() -> Int {
        checkAllCountValue
    }
}
