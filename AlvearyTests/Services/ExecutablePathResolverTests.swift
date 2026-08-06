import Foundation
import XCTest

@testable import Alveary

final class ExecutablePathResolverTests: XCTestCase {
    private var toolsDirectory: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        toolsDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: toolsDirectory)
        toolsDirectory = nil
        try super.tearDownWithError()
    }

    func testRepeatedResolutionProbesOnlyOnce() async throws {
        let path = try makeExecutable(named: "gh")
        let shell = MockShellRunner(defaultResponse: .success(makeWhichResult(path: path)))
        let resolver = DefaultExecutablePathResolver(shell: shell)

        let first = await resolver.resolveExecutablePath(for: "gh")
        let second = await resolver.resolveExecutablePath(for: "gh")

        XCTAssertEqual(first, path)
        XCTAssertEqual(second, path)
        await assertWhichProbeCount(shell, 1)
    }

    /// The actor suspends at its first `await`, so a cache alone would let a pane's
    /// detail and diff legs each spawn their own `which`.
    func testConcurrentResolutionsShareOneProbe() async throws {
        let path = try makeExecutable(named: "gh")
        let shell = MockShellRunner(defaultResponse: .success(makeWhichResult(path: path)))
        let gate = MockShellRunnerGate()
        await shell.setGate(gate)
        let resolver = DefaultExecutablePathResolver(shell: shell)

        async let first = resolver.resolveExecutablePath(for: "gh")
        async let second = resolver.resolveExecutablePath(for: "gh")
        // Let both callers reach the resolver before the single probe completes.
        for _ in 0..<200 {
            await Task.yield()
        }
        gate.open()

        let results = await [first, second]
        XCTAssertEqual(results, [path, path])
        await assertWhichProbeCount(shell, 1)
    }

    func testDistinctCandidatesAreCachedIndependently() async throws {
        let ghPath = try makeExecutable(named: "gh")
        let claudePath = try makeExecutable(named: "claude")
        let shell = MockShellRunner(defaultResponse: .success(makeWhichResult(path: ghPath)))
        await shell.enqueue(.success(makeWhichResult(path: ghPath)))
        await shell.enqueue(.success(makeWhichResult(path: claudePath)))
        let resolver = DefaultExecutablePathResolver(shell: shell)

        let resolvedGH = await resolver.resolveExecutablePath(for: "gh")
        let resolvedClaude = await resolver.resolveExecutablePath(for: "claude")

        XCTAssertEqual(resolvedGH, ghPath)
        XCTAssertEqual(resolvedClaude, claudePath)
        await assertWhichProbeCount(shell, 2)
    }

    func testVanishedCachedPathIsProbedAgain() async throws {
        let path = try makeExecutable(named: "gh")
        let shell = MockShellRunner(defaultResponse: .success(makeWhichResult(path: "")))
        await shell.enqueue(.success(makeWhichResult(path: path)))
        let resolver = DefaultExecutablePathResolver(
            shell: shell,
            fallbackExecutableDirectories: []
        )

        let cached = await resolver.resolveExecutablePath(for: "gh")
        XCTAssertEqual(cached, path)
        try FileManager.default.removeItem(atPath: path)

        // Uninstalling must invalidate the cache rather than hand callers a dead
        // path to fail at `Process.run`; the second probe finds nothing.
        let afterRemoval = await resolver.resolveExecutablePath(for: "gh")
        XCTAssertNil(afterRemoval)
        await assertWhichProbeCount(shell, 2)
    }

    /// Onboarding installs a dependency and re-checks it immediately, so a cached
    /// negative would report a freshly installed binary as still missing.
    func testFailedResolutionIsNotCached() async throws {
        let shell = MockShellRunner(defaultResponse: .success(makeWhichResult(path: "")))
        let resolver = DefaultExecutablePathResolver(
            shell: shell,
            fallbackExecutableDirectories: []
        )

        let whileMissing = await resolver.resolveExecutablePath(for: "gh")
        XCTAssertNil(whileMissing)

        let path = try makeExecutable(named: "gh")
        await shell.enqueue(.success(makeWhichResult(path: path)))

        let afterInstall = await resolver.resolveExecutablePath(for: "gh")
        XCTAssertEqual(afterInstall, path)
    }

    func testExplicitPathCandidateBypassesTheProbeEntirely() async throws {
        let path = try makeExecutable(named: "gh")
        let shell = MockShellRunner()
        let resolver = DefaultExecutablePathResolver(shell: shell)

        let resolved = await resolver.resolveExecutablePath(for: path)
        XCTAssertEqual(resolved, path)
        let missing = await resolver.resolveExecutablePath(for: "/nonexistent/gh")
        XCTAssertNil(missing)

        let invocations = await shell.invocations
        XCTAssertTrue(invocations.isEmpty)
    }

    // MARK: - Helpers

    /// Counts only the `which` spawns: a miss also fans out to login shells, so a
    /// raw invocation count would swing with the machine's shell inventory.
    private func assertWhichProbeCount(
        _ shell: MockShellRunner,
        _ expected: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        let probes = await shell.invocations.filter { $0.executable == "/usr/bin/which" }
        XCTAssertEqual(probes.count, expected, file: file, line: line)
    }

    private func makeExecutable(named name: String) throws -> String {
        let url = toolsDirectory.appendingPathComponent(name)
        try "#!/bin/sh\n".write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private func makeWhichResult(path: String) -> ShellResult {
        ShellResult(
            stdout: path.isEmpty ? "" : path + "\n",
            stderr: "",
            exitCode: path.isEmpty ? 1 : 0,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }
}
