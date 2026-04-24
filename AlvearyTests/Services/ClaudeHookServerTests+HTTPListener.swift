import Darwin
import Foundation
import XCTest

@testable import Alveary

extension ClaudeHookServerTests {
    func testHookListenerStartsOnEphemeralLoopbackPort() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty() }
        defer { listener.cancel() }

        let port = try await listener.start()

        XCTAssertGreaterThan(port, 0)
    }

    func testHookListenerReportsUnavailableWhenCancelled() async throws {
        let expectation = expectation(description: "listener unavailable")
        let listener = ClaudeHookHTTPListener(
            onUnavailable: {
                expectation.fulfill()
            },
            handler: { _ in .empty() }
        )

        _ = try await listener.start()
        listener.cancel()

        await fulfillment(of: [expectation], timeout: 0.5)
    }

    func testHookListenerDeniesOversizedRequestsWithTwoHundred() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty(statusCode: 500) }
        defer { listener.cancel() }

        let port = try await listener.start()
        let url = try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/claude/hooks/pre-tool-use"))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.httpBody = Data(repeating: UInt8(ascii: "x"), count: 300 * 1024)

        let (data, response) = try await URLSession.shared.data(for: request)

        XCTAssertEqual((response as? HTTPURLResponse)?.statusCode, 200)
        XCTAssertEqual(try hookDecision(from: data), "deny")
    }

    func testHookListenerDeniesIncompleteClosedRequestsWithTwoHundred() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty(statusCode: 500) }
        defer { listener.cancel() }

        let port = try await listener.start()
        let responseData = try readRawHTTPResponse(
            port: port,
            payload: """
            POST /claude/hooks/pre-tool-use HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: 20\r
            \r
            {}
            """
        )
        let response = String(data: responseData, encoding: .utf8)

        XCTAssertTrue(response?.hasPrefix("HTTP/1.1 200 OK") == true)
        XCTAssertEqual(try hookDecision(from: httpBody(from: responseData)), "deny")
    }

    func testHookListenerDeniesNegativeContentLengthWithTwoHundred() async throws {
        let listener = ClaudeHookHTTPListener { _ in .empty(statusCode: 500) }
        defer { listener.cancel() }

        let port = try await listener.start()
        let responseData = try readRawHTTPResponse(
            port: port,
            payload: """
            POST /claude/hooks/pre-tool-use HTTP/1.1\r
            Host: 127.0.0.1\r
            Content-Length: -1\r
            \r

            """
        )
        let response = String(data: responseData, encoding: .utf8)

        XCTAssertTrue(response?.hasPrefix("HTTP/1.1 200 OK") == true)
        XCTAssertEqual(try hookDecision(from: httpBody(from: responseData)), "deny")
    }

    private func httpBody(from responseData: Data) throws -> Data {
        let separator = Data("\r\n\r\n".utf8)
        let range = try XCTUnwrap(responseData.range(of: separator))
        return Data(responseData[range.upperBound...])
    }

    private func readRawHTTPResponse(port: UInt16, payload: String) throws -> Data {
        let socketFD = socket(AF_INET, SOCK_STREAM, 0)
        guard socketFD >= 0 else {
            throw posixError()
        }
        defer { close(socketFD) }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(port).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let connectResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                Darwin.connect(socketFD, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connectResult == 0 else {
            throw posixError()
        }

        let bytes = Array(payload.utf8)
        let sent = bytes.withUnsafeBytes { buffer in
            Darwin.write(socketFD, buffer.baseAddress, buffer.count)
        }
        guard sent == bytes.count else {
            throw posixError()
        }

        shutdown(socketFD, SHUT_WR)
        var response = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while true {
            let count = Darwin.read(socketFD, &buffer, buffer.count)
            if count > 0 {
                response.append(contentsOf: buffer.prefix(count))
            } else if count == 0 {
                return response
            } else if errno != EINTR {
                throw posixError()
            }
        }
    }

    private func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
