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

    /// `gh` 2.103 prints the code to stderr, not stdout; a flow reading only stdout never sees it.
    func testAuthenticateReadsDeviceCodeFromStandardError() async throws {
        let scriptURL = try makeExecutableScript(
            contents: """
            #!/bin/sh
            printf '\n! One-time code (AB12-CD34) copied to clipboard\n' >&2
            printf 'Open this URL to continue in your web browser: https://github.com/login/device\n' >&2
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

        XCTAssertEqual(deviceCode.code, "AB12-CD34")
        XCTAssertTrue(didAuthenticate)
    }

    /// `gh` keeps running after it prints the code — it polls GitHub for the approval — so the code
    /// must surface while the process is alive. This `gh` exits successfully only once the test has
    /// seen the code; a reader that waits for end of file would see it only after the fake gives
    /// up and exits non-zero.
    func testAuthenticateReturnsTheCodeWhileGitHubCLIIsStillRunning() async throws {
        let markerURL = FileManager.default.temporaryDirectory.appendingPathComponent("gh-code-seen-\(UUID().uuidString)")
        addTeardownBlock { try? FileManager.default.removeItem(at: markerURL) }
        let scriptURL = try makeExecutableScript(
            contents: """
            #!/bin/sh
            printf '! One-time code (LIVE-0001) copied to clipboard\n' >&2
            for _ in $(seq 1 200); do
              if [ -f '\(markerURL.path)' ]; then
                exit 0
              fi
              sleep 0.05
            done
            exit 1
            """
        )
        let service = DefaultGitHubCLIService(
            shell: MockShellRunner(),
            executableResolver: GitHubCLIExecutablePathResolverFake(path: scriptURL.path),
            authTimeout: .seconds(30)
        )

        let deviceCode = try await service.authenticate()
        try Data().write(to: markerURL)
        let didAuthenticate = try await service.awaitAuthentication()

        XCTAssertEqual(deviceCode.code, "LIVE-0001")
        XCTAssertTrue(didAuthenticate)
    }

    func testRefreshAuthenticationRequestsScopesForGitHubHost() async throws {
        let scriptURL = try makeExecutableScript(
            contents: """
            #!/bin/sh
            if [ "$*" != "auth refresh -h github.com -s notifications --clipboard" ]; then
              exit 2
            fi
            printf '! One-time code (F9B7-1C75) copied to clipboard\n' >&2
            sleep 0.1
            exit 0
            """
        )
        let service = DefaultGitHubCLIService(
            shell: MockShellRunner(),
            executableResolver: GitHubCLIExecutablePathResolverFake(path: scriptURL.path),
            authTimeout: .seconds(1)
        )

        let deviceCode = try await service.refreshAuthentication(addingScopes: ["notifications"])
        let didAuthenticate = try await service.awaitAuthentication()

        XCTAssertEqual(deviceCode.code, "F9B7-1C75")
        XCTAssertTrue(didAuthenticate)
    }

    /// A `gh` that exits without printing a code — refusing to refresh, say — must fail promptly
    /// rather than wait for output that will never come.
    func testRefreshAuthenticationFailsWhenGitHubCLIExitsWithoutCode() async throws {
        let scriptURL = try makeExecutableScript(
            contents: """
            #!/bin/sh
            printf 'The value of the GH_TOKEN environment variable is being used for authentication.\n' >&2
            exit 1
            """
        )
        let service = DefaultGitHubCLIService(
            shell: MockShellRunner(),
            executableResolver: GitHubCLIExecutablePathResolverFake(path: scriptURL.path),
            authTimeout: .seconds(1)
        )

        do {
            _ = try await service.refreshAuthentication(addingScopes: ["notifications"])
            XCTFail("Expected a parse failure.")
        } catch let error as GitHubError {
            XCTAssertEqual(error, .authParseFailed)
        }
        let didAuthenticate = try await service.awaitAuthentication()
        XCTAssertFalse(didAuthenticate)
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
