import Foundation

@testable import Alveary

class ServiceURLProtocolStub: URLProtocol, @unchecked Sendable {
    struct StubResponse: Sendable {
        let statusCode: Int
        let data: Data
        let headers: [String: String]

        init(statusCode: Int, data: Data, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.data = data
            self.headers = headers
        }
    }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var responses: [String: [StubResponse]] = [:]
    nonisolated(unsafe) private static var requests: [String] = []

    static func configure(responses: [String: [StubResponse]]) {
        lock.lock()
        self.responses = responses
        requests = []
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

        let response = Self.dequeueResponse(for: url.absoluteString)
        let httpResponse = HTTPURLResponse(
            url: url,
            statusCode: response.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: response.headers
        )

        client?.urlProtocol(self, didReceive: httpResponse ?? URLResponse(), cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: response.data)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private extension ServiceURLProtocolStub {
    static func dequeueResponse(for url: String) -> StubResponse {
        lock.lock()
        requests.append(url)
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
