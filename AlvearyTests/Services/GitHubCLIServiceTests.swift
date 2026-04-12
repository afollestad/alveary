import Darwin
import Foundation
import XCTest

@testable import Alveary

@MainActor
final class GitHubCLIServiceTests: XCTestCase {
    func testAuthenticateParsesDeviceCodeAndAwaitsSuccess() async throws {
        let scriptURL = try makeExecutableScript(
            contents: """
            #!/bin/sh
            printf '! One-time code (F9B7-1C75) copied to clipboard\n'
            sleep 0.1
            exit 0
            """
        )
        let service = DefaultGitHubCLIService(
            shell: MockShellRunner(),
            authExecutable: scriptURL.path,
            authArguments: [],
            authTimeout: .seconds(1)
        )

        let deviceCode = try await service.authenticate()
        let didAuthenticate = try await service.awaitAuthentication()
        let expectedURL = try XCTUnwrap(URL(string: "https://github.com/login/device"))

        XCTAssertEqual(deviceCode.code, "F9B7-1C75")
        XCTAssertEqual(deviceCode.verificationURL, expectedURL)
        XCTAssertTrue(didAuthenticate)
    }

    private func makeExecutableScript(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(url.path, 0o755), 0)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}
