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

    func testProviderCommandResolvesThroughLoginShellWhenWhichMissesUserPath() async throws {
        let executable = try makeExecutable(named: "claude")
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "", exitCode: 1)))
        await shell.enqueue(.success(shellResult(stdout: "shell startup noise\n__ALVEARY_EXECUTABLE_PATH__\(executable.path)\n")))
        await shell.enqueue(.success(shellResult(stdout: "1.2.3\n")))

        let service = DefaultProviderDetectionService(
            shell: shell,
            registry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry())
        )

        await service.checkProvider("claude")

        let status = await service.status(for: "claude")
        let resolvedPath = await service.resolvedPath(for: "claude")

        XCTAssertEqual(status, .connected(path: executable.path, version: "1.2.3"))
        XCTAssertEqual(resolvedPath, executable.path)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)
        XCTAssertEqual(invocations[0].executable, "/usr/bin/which")
        XCTAssertEqual(invocations[0].args, ["claude"])
        XCTAssertEqual(
            invocations[1].args,
            [
                "-lc",
                "resolved=$(command -v 'claude') && printf '%s%s\\n' '__ALVEARY_EXECUTABLE_PATH__' \"$resolved\""
            ]
        )
        XCTAssertEqual(invocations[2].executable, executable.path)
        XCTAssertEqual(invocations[2].args, ["--version"])
    }

    func testProviderCommandResolvesThroughFallbackDirectoryWhenShellPathMisses() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let executable = try makeExecutable(named: "claude", in: directory)
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "", exitCode: 1)))

        let service = DefaultProviderDetectionService(
            shell: shell,
            registry: DefaultProviderRegistry(agentRegistry: DefaultAgentRegistry()),
            fallbackExecutableDirectories: [directory.path]
        )

        await service.checkProvider("claude")

        let resolvedPath = await service.resolvedPath(for: "claude")

        XCTAssertEqual(resolvedPath, executable.path)
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

    private func makeExecutable(
        named name: String,
        in directory: URL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    ) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let executable = directory.appendingPathComponent(name)
        try "#!/bin/sh\n".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
        return executable
    }
}
