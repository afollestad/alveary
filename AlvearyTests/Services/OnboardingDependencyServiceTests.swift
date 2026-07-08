import Foundation
import XCTest

@testable import Alveary

@MainActor
final class OnboardingDependencyServiceTests: XCTestCase {
    func testGitHubCLIInstallBootstrapsHomebrewBeforeBrewInstallWhenBrewIsMissing() async throws {
        let gitHubCLI = OnboardingGitHubCLIFake(installedVersions: [nil, "gh version 2.89.0"])
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "homebrew installed")))
        await shell.enqueue(.success(shellResult(stdout: "gh installed")))
        let resolver = OnboardingExecutablePathResolverFake(paths: ["brew": [nil, "/opt/homebrew/bin/brew"]])
        let service = makeService(gitHubCLI: gitHubCLI, shell: shell, executableResolver: resolver)

        let status = try await service.install(.githubCLI)

        XCTAssertEqual(status, OnboardingDependencyStatus(dependency: .githubCLI, state: .installed(detail: "gh version 2.89.0")))
        let resolverInvocations = await resolver.recordedInvocations()
        XCTAssertEqual(resolverInvocations, ["brew", "brew"])

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 2)
        XCTAssertEqual(invocations[0].executable, "/bin/bash")
        XCTAssertEqual(
            invocations[0].args,
            ["-c", "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"]
        )
        XCTAssertNil(invocations[0].environment)
        assertInstallerOptions(invocations[0])

        XCTAssertEqual(invocations[1].executable, "/opt/homebrew/bin/brew")
        XCTAssertEqual(invocations[1].args, ["install", "gh"])
        XCTAssertEqual(invocations[1].environment, ["NONINTERACTIVE": "1"])
        assertInstallerOptions(invocations[1])
    }

    func testGitHubCLIInstallUsesResolvedBrewWithoutBootstrapWhenBrewExists() async throws {
        let gitHubCLI = OnboardingGitHubCLIFake(installedVersions: [nil, "gh version 2.89.0"])
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "gh installed")))
        let resolver = OnboardingExecutablePathResolverFake(paths: ["brew": ["/usr/local/bin/brew"]])
        let service = makeService(gitHubCLI: gitHubCLI, shell: shell, executableResolver: resolver)

        _ = try await service.install(.githubCLI)

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.executable), ["/usr/local/bin/brew"])
        XCTAssertEqual(invocations.first?.environment, ["NONINTERACTIVE": "1"])
        let resolverInvocations = await resolver.recordedInvocations()
        XCTAssertEqual(resolverInvocations, ["brew"])
    }

    func testCodexInstallUsesRegistryCommandCodexEnvAndNullStdin() async throws {
        let providerDetection = OnboardingProviderDetectionFake(
            snapshots: [
                "codex": [
                    ProviderSnapshot(status: .missing, path: nil),
                    ProviderSnapshot(status: .needsKey, path: "/Users/alveary/.codex/bin/codex")
                ]
            ]
        )
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "codex installed")))
        let service = makeService(providerDetection: providerDetection, shell: shell)

        let status = try await service.install(.codex)

        XCTAssertEqual(
            status,
            OnboardingDependencyStatus(
                dependency: .codex,
                state: .installed(detail: "/Users/alveary/.codex/bin/codex")
            )
        )
        let providerChecks = await providerDetection.recordedChecks()
        XCTAssertEqual(providerChecks, ["codex", "codex"])

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.executable, "/bin/bash")
        XCTAssertEqual(invocation.args, ["-lc", "curl -fsSL https://chatgpt.com/codex/install.sh | sh"])
        XCTAssertEqual(invocation.environment, ["CODEX_NON_INTERACTIVE": "1"])
        assertInstallerOptions(invocation)
    }

    func testClaudeInstallDoesNotApplyNonInteractiveEnvironment() async throws {
        let providerDetection = OnboardingProviderDetectionFake(
            snapshots: [
                "claude": [
                    ProviderSnapshot(status: .missing, path: nil),
                    ProviderSnapshot(status: .needsKey, path: "/Users/alveary/.claude/local/claude")
                ]
            ]
        )
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "claude installed")))
        let service = makeService(providerDetection: providerDetection, shell: shell)

        _ = try await service.install(.claude)

        let invocations = await shell.invocations
        let invocation = try XCTUnwrap(invocations.first)
        XCTAssertEqual(invocation.executable, "/bin/bash")
        XCTAssertEqual(invocation.args, ["-lc", "curl -fsSL https://claude.ai/install.sh | bash"])
        XCTAssertNil(invocation.environment)
        assertInstallerOptions(invocation)
    }

    func testOptionalStatusTreatsResolvedPathAsInstalledEvenWhenProviderNeedsSetup() async {
        let providerDetection = OnboardingProviderDetectionFake(
            snapshots: [
                "claude": [
                    ProviderSnapshot(status: .needsKey, path: "/Users/alveary/.claude/local/claude")
                ]
            ]
        )
        let service = makeService(providerDetection: providerDetection)

        let status = await service.status(for: .claude)

        XCTAssertEqual(
            status,
            OnboardingDependencyStatus(
                dependency: .claude,
                state: .installed(detail: "/Users/alveary/.claude/local/claude")
            )
        )
    }

    func testGitHubCLIPostconditionFailureIncludesInstallerOutput() async throws {
        let gitHubCLI = OnboardingGitHubCLIFake(installedVersions: [nil, nil])
        let shell = MockShellRunner()
        await shell.enqueue(.success(shellResult(stdout: "installed somewhere")))
        let resolver = OnboardingExecutablePathResolverFake(paths: ["brew": ["/opt/homebrew/bin/brew"]])
        let service = makeService(gitHubCLI: gitHubCLI, shell: shell, executableResolver: resolver)

        do {
            _ = try await service.install(.githubCLI)
            XCTFail("Expected postcondition failure.")
        } catch let error as OnboardingDependencyInstallError {
            XCTAssertTrue(error.message.contains("`brew install gh` finished, but `gh` could not be found."))
            XCTAssertTrue(error.message.contains("installed somewhere"))
        } catch {
            XCTFail("Expected OnboardingDependencyInstallError, got \(error).")
        }
    }

    func testCommandFailureIncludesExitCodeOutputAndTruncationNotice() async throws {
        let providerDetection = OnboardingProviderDetectionFake(
            snapshots: [
                "codex": [
                    ProviderSnapshot(status: .missing, path: nil)
                ]
            ]
        )
        let shell = MockShellRunner()
        await shell.enqueue(
            .success(shellResult(stderr: "curl failed", exitCode: 7, stdoutWasTruncated: true))
        )
        let service = makeService(providerDetection: providerDetection, shell: shell)

        do {
            _ = try await service.install(.codex)
            XCTFail("Expected command failure.")
        } catch let error as OnboardingDependencyInstallError {
            XCTAssertTrue(error.message.contains("`/bin/bash` failed with exit code 7."))
            XCTAssertTrue(error.message.contains("curl failed"))
            XCTAssertTrue(error.message.contains("Output was truncated."))
        } catch {
            XCTFail("Expected OnboardingDependencyInstallError, got \(error).")
        }
    }

    func testCancellationPropagatesWithoutWrapping() async {
        let providerDetection = OnboardingProviderDetectionFake(
            snapshots: [
                "codex": [
                    ProviderSnapshot(status: .missing, path: nil)
                ]
            ]
        )
        let service = makeService(providerDetection: providerDetection, shell: CancellingShellRunner())

        do {
            _ = try await service.install(.codex)
            XCTFail("Expected cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error).")
        }
    }

    private func makeService(
        gitHubCLI: GitHubCLIService = OnboardingGitHubCLIFake(installedVersions: [nil]),
        providerDetection: any ProviderDetectionService = OnboardingProviderDetectionFake(),
        agentRegistry: AgentRegistry = DefaultAgentRegistry(),
        shell: any ShellRunner = MockShellRunner(),
        executableResolver: any ExecutablePathResolving = OnboardingExecutablePathResolverFake()
    ) -> DefaultOnboardingDependencyService {
        DefaultOnboardingDependencyService(
            gitHubCLI: gitHubCLI,
            providerDetection: providerDetection,
            agentRegistry: agentRegistry,
            shell: shell,
            executableResolver: executableResolver
        )
    }

    private func assertInstallerOptions(
        _ invocation: MockShellRunner.Invocation,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(invocation.standardInput, .nullDevice, file: file, line: line)
        XCTAssertEqual(invocation.timeout, .seconds(1_800), file: file, line: line)
        XCTAssertEqual(invocation.stdoutLimitBytes, 128 * 1024, file: file, line: line)
        XCTAssertEqual(invocation.stderrLimitBytes, 128 * 1024, file: file, line: line)
    }
}

private func shellResult(
    stdout: String = "",
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

@MainActor
private final class OnboardingGitHubCLIFake: GitHubCLIService, @unchecked Sendable {
    private var installedVersions: [String?]
    private(set) var checkInstalledCallCount = 0

    init(installedVersions: [String?]) {
        self.installedVersions = installedVersions
    }

    func checkInstalled() async -> String? {
        checkInstalledCallCount += 1
        guard !installedVersions.isEmpty else {
            return nil
        }
        if installedVersions.count == 1 {
            return installedVersions[0]
        }
        return installedVersions.removeFirst()
    }

    func isAuthenticated() async -> Bool {
        false
    }

    func authenticate() async throws -> GitHubDeviceCode {
        throw GitHubError.authLaunchFailed("Not implemented")
    }

    func awaitAuthentication() async throws -> Bool {
        false
    }

    func cancelAuthentication() {}
}

private struct ProviderSnapshot: Sendable {
    let status: ProviderStatus
    let path: String?
}

private actor OnboardingProviderDetectionFake: ProviderDetectionService {
    private var snapshots: [String: [ProviderSnapshot]]
    private var checkCounts: [String: Int] = [:]
    private var checks: [String] = []

    init(snapshots: [String: [ProviderSnapshot]] = [:]) {
        self.snapshots = snapshots
    }

    func resolvedPath(for providerId: String) -> String? {
        snapshot(for: providerId).path
    }

    func status(for providerId: String) -> ProviderStatus {
        snapshot(for: providerId).status
    }

    func checkAllProviders() async {
        for providerId in snapshots.keys.sorted() {
            await checkProvider(providerId)
        }
    }

    func checkProvider(_ providerId: String) async {
        checks.append(providerId)
        checkCounts[providerId, default: 0] += 1
    }

    func recordedChecks() -> [String] {
        checks
    }

    private func snapshot(for providerId: String) -> ProviderSnapshot {
        let providerSnapshots = snapshots[providerId] ?? [ProviderSnapshot(status: .missing, path: nil)]
        let checkCount = checkCounts[providerId, default: 0]
        let index = min(max(checkCount - 1, 0), providerSnapshots.count - 1)
        return providerSnapshots[index]
    }
}

private actor OnboardingExecutablePathResolverFake: ExecutablePathResolving {
    private var paths: [String: [String?]]
    private var invocations: [String] = []

    init(paths: [String: [String?]] = [:]) {
        self.paths = paths
    }

    func resolveExecutablePath(for candidate: String) async -> String? {
        invocations.append(candidate)
        guard var queue = paths[candidate],
              !queue.isEmpty else {
            return nil
        }
        if queue.count == 1 {
            return queue[0]
        }
        let result = queue.removeFirst()
        paths[candidate] = queue
        return result
    }

    func recordedInvocations() -> [String] {
        invocations
    }
}

private struct CancellingShellRunner: ShellRunner {
    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        throw CancellationError()
    }
}
