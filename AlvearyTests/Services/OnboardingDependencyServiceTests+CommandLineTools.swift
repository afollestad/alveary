import Foundation
import XCTest

@testable import Alveary

@MainActor
extension OnboardingDependencyServiceTests {
    func testCommandLineToolsStatusProbesXcodeSelectAndTheDeveloperDirectoryGit() async {
        let shell = CommandLineToolsShellFake(developerDirectory: "/Library/Developer/CommandLineTools")
        let service = makeCommandLineToolsService(shell: shell)

        let status = await service.status(for: .commandLineTools)

        XCTAssertEqual(
            status,
            OnboardingDependencyStatus(dependency: .commandLineTools, state: .installed(detail: "git version 2.51.0"))
        )

        let invocations = await shell.invocations
        XCTAssertEqual(invocations[0].executable, "/usr/bin/xcode-select")
        XCTAssertEqual(invocations[0].args, ["-p"])
        XCTAssertEqual(invocations[0].timeout, .seconds(3))
        XCTAssertEqual(invocations[0].standardInput, .nullDevice)

        // Full Xcode also ships git under its developer directory, so detection must follow
        // whatever `xcode-select -p` reports rather than hardcoding the CommandLineTools path.
        XCTAssertEqual(invocations[1].executable, "/Library/Developer/CommandLineTools/usr/bin/git")
        XCTAssertEqual(invocations[1].args, ["--version"])
    }

    func testCommandLineToolsStatusFollowsAFullXcodeDeveloperDirectory() async {
        let shell = CommandLineToolsShellFake(developerDirectory: "/Applications/Xcode.app/Contents/Developer")
        let service = makeCommandLineToolsService(shell: shell)

        let status = await service.status(for: .commandLineTools)

        XCTAssertTrue(status.isInstalled)
        let invocations = await shell.invocations
        XCTAssertEqual(invocations[1].executable, "/Applications/Xcode.app/Contents/Developer/usr/bin/git")
    }

    func testCommandLineToolsStatusNeverSpawnsTheGitShimWhenXcodeSelectFails() async {
        let shell = CommandLineToolsShellFake(developerDirectory: nil)
        let service = makeCommandLineToolsService(shell: shell)

        let status = await service.status(for: .commandLineTools)

        XCTAssertEqual(status, OnboardingDependencyStatus(dependency: .commandLineTools, state: .missing))

        // Running `/usr/bin/git` is what pops Apple's system-modal installer dialog.
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.executable), ["/usr/bin/xcode-select"])
        XCTAssertFalse(invocations.contains { $0.executable == "/usr/bin/git" })
    }

    func testCommandLineToolsStatusIsMissingWhenTheDeveloperDirectoryHasNoGit() async {
        // `DEVELOPER_DIR=/nonexistent xcode-select -p` exits 0 and echoes the bogus path, so a
        // successful probe is not proof on its own — the executable check is what decides.
        let shell = CommandLineToolsShellFake(developerDirectory: "/nonexistent", materializesGit: false)
        let service = makeCommandLineToolsService(shell: shell)

        let status = await service.status(for: .commandLineTools)

        XCTAssertEqual(status, OnboardingDependencyStatus(dependency: .commandLineTools, state: .missing))
        let invocations = await shell.invocations
        XCTAssertEqual(invocations.map(\.executable), ["/usr/bin/xcode-select"])
    }

    func testCommandLineToolsInstallLaunchesAppleInstallerThenPollsUntilDetected() async throws {
        let shell = CommandLineToolsShellFake(developerDirectory: nil, developerDirectoryAfterProbes: 3)
        defer { CommandLineToolsShellFake.removeStagedDeveloperDirectory() }
        let service = makeCommandLineToolsService(shell: shell)

        let status = try await service.install(.commandLineTools)

        XCTAssertTrue(status.isInstalled)
        let invocations = await shell.invocations

        // `install` re-checks first, so the Apple installer launch is not the very first invocation.
        let launchIndex = try XCTUnwrap(invocations.firstIndex { $0.args == ["--install"] })
        XCTAssertEqual(invocations[launchIndex].executable, "/usr/bin/xcode-select")
        XCTAssertEqual(invocations[launchIndex].standardInput, .nullDevice)

        let probesAfterLaunch = invocations[(launchIndex + 1)...].filter { $0.args == ["-p"] }
        XCTAssertGreaterThan(probesAfterLaunch.count, 1, "Expected the launch to be followed by detection polls")
    }

    func testCommandLineToolsInstallIsCancellable() async {
        let shell = CommandLineToolsShellFake(developerDirectory: nil)
        let service = makeCommandLineToolsService(shell: shell)

        let task = Task { try await service.install(.commandLineTools) }
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("Expected the poll to observe cancellation.")
        } catch is CancellationError {
            // Expected.
        } catch {
            XCTFail("Expected CancellationError, got \(error).")
        }
    }

    private func makeCommandLineToolsService(shell: CommandLineToolsShellFake) -> DefaultOnboardingDependencyService {
        DefaultOnboardingDependencyService(
            gitHubCLI: CommandLineToolsGitHubCLIStub(),
            providerDetection: CommandLineToolsProviderDetectionStub(),
            agentRegistry: DefaultAgentRegistry(),
            shell: shell,
            executableResolver: CommandLineToolsResolverStub(),
            standaloneGitHubCLIInstaller: CommandLineToolsStandaloneInstallerStub(),
            commandLineToolsPollInterval: .milliseconds(1)
        )
    }
}

/// Answers `xcode-select -p` and the developer-directory `git --version` probe. The git executable
/// is materialized on disk because detection requires an executable file at that path.
private actor CommandLineToolsShellFake: ShellRunner {
    private let developerDirectory: String?
    private let developerDirectoryAfterProbes: Int?
    private let materializesGit: Bool
    private var probeCount = 0
    private(set) var invocations: [MockShellRunner.Invocation] = []

    init(
        developerDirectory: String?,
        developerDirectoryAfterProbes: Int? = nil,
        materializesGit: Bool = true
    ) {
        self.developerDirectory = developerDirectory
        self.developerDirectoryAfterProbes = developerDirectoryAfterProbes
        self.materializesGit = materializesGit
    }

    func run(
        executable: String,
        args: [String],
        in directory: String?,
        options: ShellRunOptions
    ) async throws -> ShellResult {
        invocations.append(
            MockShellRunner.Invocation(
                executable: executable,
                args: args,
                directory: directory,
                environment: options.environment,
                timeout: options.timeout,
                stdoutLimitBytes: options.stdoutLimitBytes,
                stderrLimitBytes: options.stderrLimitBytes,
                standardInput: options.standardInput
            )
        )

        if executable == "/usr/bin/xcode-select" && args == ["-p"] {
            probeCount += 1
            guard let path = resolvedDeveloperDirectory() else {
                return result(stdout: "", exitCode: 2)
            }
            try materializeGit(in: path)
            return result(stdout: "\(path)\n", exitCode: 0)
        }
        if args == ["--version"] {
            return result(stdout: "git version 2.51.0\n", exitCode: 0)
        }
        return result(stdout: "", exitCode: 0)
    }

    private func resolvedDeveloperDirectory() -> String? {
        if let developerDirectory {
            return developerDirectory
        }
        guard let developerDirectoryAfterProbes, probeCount >= developerDirectoryAfterProbes else {
            return nil
        }
        return Self.stagedDeveloperDirectory
    }

    nonisolated static var stagedDeveloperDirectory: String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("CommandLineToolsShellFake", isDirectory: true)
            .path
    }

    nonisolated static func removeStagedDeveloperDirectory() {
        try? FileManager.default.removeItem(atPath: stagedDeveloperDirectory)
    }

    private func materializeGit(in developerDirectory: String) throws {
        guard materializesGit else {
            return
        }
        let gitURL = URL(fileURLWithPath: developerDirectory, isDirectory: true)
            .appendingPathComponent("usr/bin/git")
        guard !FileManager.default.isExecutableFile(atPath: gitURL.path) else {
            return
        }
        try FileManager.default.createDirectory(
            at: gitURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(
            atPath: gitURL.path,
            contents: Data("#!/bin/sh\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )
    }

    private func result(stdout: String, exitCode: Int32) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stderr: "",
            exitCode: exitCode,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }
}

@MainActor
private final class CommandLineToolsGitHubCLIStub: GitHubCLIService, @unchecked Sendable {
    func checkInstalled() async -> String? { nil }
    func isAuthenticated() async -> Bool { false }
    func authenticate() async throws -> GitHubDeviceCode { throw GitHubError.authLaunchFailed("Not implemented") }
    func awaitAuthentication() async throws -> Bool { false }
    func cancelAuthentication() {}
}

private actor CommandLineToolsProviderDetectionStub: ProviderDetectionService {
    func resolvedPath(for providerId: String) -> String? { nil }
    func status(for providerId: String) -> ProviderStatus { .missing }
    func checkAllProviders() async {}
    func checkProvider(_ providerId: String) async {}
}

private actor CommandLineToolsResolverStub: ExecutablePathResolving {
    func resolveExecutablePath(for candidate: String) async -> String? { nil }
}

@MainActor
private final class CommandLineToolsStandaloneInstallerStub: StandaloneGitHubCLIInstalling, @unchecked Sendable {
    func install() async throws {}
}
