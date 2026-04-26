import XCTest

@testable import Alveary

final class ProviderDetectionServiceTests: XCTestCase {
    func testUncheckedProvidersRemainUncheckedUntilProbeRuns() async {
        let shell = MockShellRunner()
        let service = DefaultProviderDetectionService(
            shell: shell,
            registry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry())
        )

        let status = await service.status(for: "claude")
        let resolvedPath = await service.resolvedPath(for: "claude")

        XCTAssertEqual(status, .unchecked)
        XCTAssertNil(resolvedPath)
    }

    func testProviderCommandResolvesThroughWhichBeforeVersionCheck() async throws {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "/tmp/claude\n")))
        await shell.enqueue(.success(shellResult(stdout: "1.2.3\n")))

        let service = DefaultProviderDetectionService(
            shell: shell,
            registry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry())
        )

        await service.checkProvider("claude")

        let status = await service.status(for: "claude")
        let resolvedPath = await service.resolvedPath(for: "claude")

        XCTAssertEqual(status, .connected(path: "/tmp/claude", version: "1.2.3"))
        XCTAssertEqual(resolvedPath, "/tmp/claude")

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].executable, "/usr/bin/which")
        XCTAssertEqual(invocations[0].args, ["claude"])
        XCTAssertEqual(invocations[1].executable, "/tmp/claude")
        XCTAssertEqual(invocations[1].args, ["--version"])
    }

    func testFailedVersionCheckCanBeClassifiedAsNeedsKey() async {
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "/usr/local/bin/claude\n")))
        await shell.enqueue(.success(shellResult(stdout: "", stderr: "not authenticated", exitCode: 1)))

        let service = DefaultProviderDetectionService(
            shell: shell,
            registry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry())
        )

        await service.checkProvider("claude")

        let status = await service.status(for: "claude")
        let resolvedPath = await service.resolvedPath(for: "claude")

        XCTAssertEqual(status, .needsKey)
        XCTAssertEqual(resolvedPath, "/usr/local/bin/claude")
    }

    private func shellResult(
        stdout: String,
        stderr: String = "",
        exitCode: Int32 = 0,
        stdoutWasTruncated: Bool = false,
        stderrWasTruncated: Bool = false
    ) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stderr: stderr,
            exitCode: exitCode,
            stdoutWasTruncated: stdoutWasTruncated,
            stderrWasTruncated: stderrWasTruncated
        )
    }
}
