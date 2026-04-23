import Foundation
import Network

struct ClaudeHookHTTPRequest: Sendable {
    let authorization: String?
    let body: Data
}

struct ClaudeHookHTTPResponse: Sendable {
    let statusCode: Int
    let body: Data?

    static func empty(statusCode: Int = 200) -> ClaudeHookHTTPResponse {
        ClaudeHookHTTPResponse(statusCode: statusCode, body: nil)
    }

    static func json(_ object: [String: Any], statusCode: Int = 200) -> ClaudeHookHTTPResponse {
        let body = try? JSONSerialization.data(withJSONObject: object, options: [])
        return ClaudeHookHTTPResponse(statusCode: statusCode, body: body)
    }

    static func preToolUseDeny(reason: String) -> ClaudeHookHTTPResponse {
        json([
            "hookSpecificOutput": [
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason
            ]
        ])
    }
}

final class ClaudeHookHTTPListener: @unchecked Sendable {
    typealias Handler = @Sendable (ClaudeHookHTTPRequest) async -> ClaudeHookHTTPResponse
    typealias UnavailableHandler = @Sendable () -> Void

    private static let maxRequestBytes = 256 * 1024

    private let queue = DispatchQueue(label: "app.alveary.claude-hook-listener")
    private let handler: Handler
    private let onUnavailable: UnavailableHandler?
    private var listener: NWListener?

    init(onUnavailable: UnavailableHandler? = nil, handler: @escaping Handler) {
        self.onUnavailable = onUnavailable
        self.handler = handler
    }

    func start() async throws -> UInt16 {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(
            host: .ipv4(.loopback),
            port: NWEndpoint.Port(rawValue: 0) ?? .any
        )

        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            self?.handle(connection)
        }

        return try await withCheckedThrowingContinuation { continuation in
            let resumeGuard = ClaudeHookListenerStartContinuation(continuation: continuation)

            listener.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    if let port = listener.port?.rawValue {
                        resumeGuard.resume(.success(port))
                    } else {
                        resumeGuard.resume(.failure(ClaudeHookListenerError.missingPort))
                    }
                case .failed(let error):
                    resumeGuard.resume(.failure(error))
                    self.onUnavailable?()
                case .cancelled:
                    resumeGuard.resume(.failure(ClaudeHookListenerError.cancelled))
                    self.onUnavailable?()
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func cancel() {
        listener?.cancel()
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else {
                connection.cancel()
                return
            }
            guard error == nil else {
                connection.cancel()
                return
            }

            var nextBuffer = buffer
            if let data {
                nextBuffer.append(data)
            }
            guard nextBuffer.count <= Self.maxRequestBytes else {
                self.send(.preToolUseDeny(reason: "Alveary hook request was too large"), on: connection)
                return
            }

            guard let request = Self.parseRequest(from: nextBuffer) else {
                guard !isComplete else {
                    self.send(.preToolUseDeny(reason: "Alveary hook request was incomplete"), on: connection)
                    return
                }
                self.receive(on: connection, buffer: nextBuffer)
                return
            }

            Task {
                let response = await self.handler(request)
                self.send(response, on: connection)
            }
        }
    }

    private func send(_ response: ClaudeHookHTTPResponse, on connection: NWConnection) {
        let statusText = response.statusCode == 200 ? "OK" : "Error"
        let body = response.body ?? Data()
        var headers = [
            "HTTP/1.1 \(response.statusCode) \(statusText)",
            "Content-Length: \(body.count)",
            "Connection: close"
        ]
        if response.body != nil {
            headers.append("Content-Type: application/json")
        }
        headers.append("")
        headers.append("")

        var payload = Data(headers.joined(separator: "\r\n").utf8)
        payload.append(body)
        connection.send(content: payload, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static func parseRequest(from data: Data) -> ClaudeHookHTTPRequest? {
        guard let markerRange = data.range(of: Data("\r\n\r\n".utf8)) else {
            return nil
        }

        let headerData = data[..<markerRange.lowerBound]
        guard let headerText = String(data: headerData, encoding: .utf8) else {
            return nil
        }

        let headers = parseHeaders(headerText)
        guard let contentLength = Int(headers["content-length"] ?? "0"),
              contentLength >= 0 else {
            return nil
        }
        let bodyStart = markerRange.upperBound
        guard data.count - bodyStart >= contentLength else {
            return nil
        }

        let body = Data(data[bodyStart..<(bodyStart + contentLength)])
        return ClaudeHookHTTPRequest(
            authorization: headers["authorization"],
            body: body
        )
    }

    private static func parseHeaders(_ text: String) -> [String: String] {
        var headers: [String: String] = [:]
        for line in text.split(separator: "\r\n").dropFirst() {
            guard let separator = line.firstIndex(of: ":") else {
                continue
            }
            let name = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            headers[name] = value
        }
        return headers
    }
}

private final class ClaudeHookListenerStartContinuation: @unchecked Sendable {
    private let lock = NSLock()
    private let continuation: CheckedContinuation<UInt16, Error>
    private var didResume = false

    init(continuation: CheckedContinuation<UInt16, Error>) {
        self.continuation = continuation
    }

    func resume(_ result: Result<UInt16, Error>) {
        lock.lock()
        defer { lock.unlock() }
        guard !didResume else {
            return
        }
        didResume = true
        continuation.resume(with: result)
    }
}

enum ClaudeHookListenerError: LocalizedError {
    case missingPort
    case cancelled

    var errorDescription: String? {
        switch self {
        case .missingPort:
            return "Claude hook listener started without an assigned port"
        case .cancelled:
            return "Claude hook listener was cancelled before startup completed"
        }
    }
}
