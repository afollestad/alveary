import Darwin
import Foundation
import XCTest

@testable import Alveary

@MainActor
final class GitHubCLIServiceTests: XCTestCase {
    func testCheckInstalledUsesResolvedGitHubCLIPath() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "gh version 2.89.0\n")))
        let service = DefaultGitHubCLIService(
            shell: shell,
            executableResolver: GitHubCLIExecutablePathResolverFake(path: "/opt/homebrew/bin/gh")
        )

        let version = await service.checkInstalled()

        XCTAssertEqual(version, "gh version 2.89.0")
        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/gh")
        XCTAssertEqual(invocation.args, ["--version"])
    }

    func testCheckInstalledTreatsUnresolvedGitHubCLIAsMissing() async {
        let shell = MockShellRunner()
        let service = DefaultGitHubCLIService(
            shell: shell,
            executableResolver: GitHubCLIExecutablePathResolverFake(path: nil)
        )

        let version = await service.checkInstalled()

        XCTAssertNil(version)
        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    func testAuthenticationStatusUsesResolvedGitHubCLIPath() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "Logged in\n")))
        let service = DefaultGitHubCLIService(
            shell: shell,
            executableResolver: GitHubCLIExecutablePathResolverFake(path: "/opt/homebrew/bin/gh")
        )

        let isAuthenticated = await service.isAuthenticated()

        XCTAssertTrue(isAuthenticated)
        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.executable, "/opt/homebrew/bin/gh")
        XCTAssertEqual(invocation.args, ["auth", "status"])
    }

    func testAuthenticateParsesDeviceCodeAndAwaitsSuccess() async throws {
        let scriptURL = try makeExecutableScript(
            contents: """
            #!/bin/sh
            if [ "$1" != "auth" ] || [ "$2" != "login" ] || [ "$3" != "--web" ] || [ "$4" != "--clipboard" ]; then
              exit 2
            fi
            printf '! One-time code (F9B7-1C75) copied to clipboard\n'
            sleep 0.1
            exit 0
            """
        )
        let service = DefaultGitHubCLIService(
            shell: MockShellRunner(),
            executableResolver: GitHubCLIExecutablePathResolverFake(path: scriptURL.path),
            authTimeout: .seconds(1)
        )

        let deviceCode = try await service.authenticate()
        let didAuthenticate = try await service.awaitAuthentication()
        let expectedURL = try XCTUnwrap(URL(string: "https://github.com/login/device"))

        XCTAssertEqual(deviceCode.code, "F9B7-1C75")
        XCTAssertEqual(deviceCode.verificationURL, expectedURL)
        XCTAssertTrue(didAuthenticate)
    }

    func testAuthenticateFailsWhenGitHubCLIPathCannotBeResolved() async {
        let service = DefaultGitHubCLIService(
            shell: MockShellRunner(),
            executableResolver: GitHubCLIExecutablePathResolverFake(path: nil),
            authTimeout: .seconds(1)
        )

        do {
            _ = try await service.authenticate()
            XCTFail("Expected missing GitHub CLI failure.")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .authLaunchFailed("GitHub CLI is not installed."))
        } catch {
            XCTFail("Expected GitHubError, got \(error).")
        }
    }

    private func makeExecutableScript(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try contents.write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(chmod(url.path, 0o755), 0)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }
}

private func shellResult(
    stdout: String = "",
    stderr: String = "",
    exitCode: Int32 = 0
) -> ShellResult {
    ShellResult(
        stdout: stdout,
        stderr: stderr,
        exitCode: exitCode,
        stdoutWasTruncated: false,
        stderrWasTruncated: false
    )
}

private struct GitHubCLIExecutablePathResolverFake: ExecutablePathResolving {
    let path: String?

    func resolveExecutablePath(for candidate: String) async -> String? {
        XCTAssertEqual(candidate, "gh")
        return path
    }
}
