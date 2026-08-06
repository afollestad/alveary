import Foundation
import XCTest

@testable import Alveary

@MainActor
final class StandaloneGitHubCLIInstallerTests: XCTestCase {
    /// Unique per test instance so each install writes into its own tree. The installer creates
    /// every directory it needs, so nothing has to exist up front.
    private nonisolated let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("StandaloneGitHubCLIInstallerTests", isDirectory: true)
        .appendingPathComponent(UUID().uuidString, isDirectory: true)

    override func tearDown() {
        try? FileManager.default.removeItem(at: rootDirectory)
        super.tearDown()
    }

    func testInstallDownloadsExtractsAndCopiesExecutable() async throws {
        let shell = ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64")
        let installDirectory = rootDirectory.appendingPathComponent("bin", isDirectory: true)
        let installer = makeInstaller(shell: shell, installDirectory: installDirectory)

        try await installer.install()

        let invocations = await shell.invocations
        XCTAssertEqual(invocations.count, 3)

        XCTAssertEqual(invocations[0].executable, "/usr/bin/curl")
        XCTAssertEqual(
            invocations[0].args,
            ["-fsSL", "https://api.github.com/repos/cli/cli/releases/latest"]
        )

        // The tag keeps its `v`, the asset filename drops it.
        XCTAssertEqual(invocations[1].executable, "/usr/bin/curl")
        XCTAssertEqual(invocations[1].args.first, "-fsSL")
        XCTAssertEqual(
            invocations[1].args.last,
            "https://github.com/cli/cli/releases/download/v2.63.2/gh_2.63.2_macOS_arm64.zip"
        )

        XCTAssertEqual(invocations[2].executable, "/usr/bin/ditto")
        XCTAssertEqual(Array(invocations[2].args.prefix(2)), ["-x", "-k"])

        let installedPath = installDirectory.appendingPathComponent("gh").path
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installedPath))
        let permissions = try FileManager.default.attributesOfItem(atPath: installedPath)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.int16Value, 0o755)
    }

    func testEveryStepRunsBoundedWithNullStdin() async throws {
        let shell = ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64")
        try await makeInstaller(shell: shell).install()

        for invocation in await shell.invocations {
            XCTAssertEqual(invocation.standardInput, .nullDevice)
            XCTAssertNotNil(invocation.timeout)
            XCTAssertNotNil(invocation.stdoutLimitBytes)
            XCTAssertNotNil(invocation.stderrLimitBytes)
        }
    }

    func testUnreachableGitHubFailsWithActionableGuidanceInsteadOfSucceeding() async throws {
        // Offline `curl` used to leave `bash -c ""`, which exits 0 and read as a broken install.
        let shell = ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64", metadataExitCode: 6)

        await assertInstallFails(makeInstaller(shell: shell)) { message in
            XCTAssertTrue(message.contains("Could not reach GitHub"))
            XCTAssertTrue(message.contains("https://cli.github.com"))
        }
    }

    func testFailedDownloadFailsWithActionableGuidance() async throws {
        let shell = ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64", downloadExitCode: 22)

        await assertInstallFails(makeInstaller(shell: shell)) { message in
            XCTAssertTrue(message.contains("Could not download the GitHub CLI."))
        }
    }

    func testUnexpectedReleaseMetadataFails() async throws {
        let shell = ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64", metadataBody: "<html>nope</html>")

        await assertInstallFails(makeInstaller(shell: shell)) { message in
            XCTAssertTrue(message.contains("unexpected response"))
        }
    }

    func testMissingExecutableAfterExtractionFails() async throws {
        let shell = ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64", extractsExecutable: false)

        await assertInstallFails(makeInstaller(shell: shell)) { message in
            XCTAssertTrue(message.contains("did not contain the expected `gh` executable"))
        }
    }

    func testWorkingDirectoryIsCleanedUpOnSuccessAndOnFailure() async throws {
        let scratchRoot = rootDirectory
            .appendingPathComponent("tmp", isDirectory: true)
            .appendingPathComponent("AlvearyGitHubCLIInstall", isDirectory: true)

        try await makeInstaller(shell: ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64")).install()
        XCTAssertEqual(try scratchContents(of: scratchRoot), [], "A successful install must not leave a download tree behind")

        await assertInstallFails(
            makeInstaller(shell: ExtractingShellRunnerFake(releaseTag: "v2.63.2", architecture: "arm64", downloadExitCode: 22))
        ) { _ in }
        XCTAssertEqual(try scratchContents(of: scratchRoot), [], "A failed install must not leave a download tree behind")
    }

    private func scratchContents(of directory: URL) throws -> [String] {
        guard FileManager.default.fileExists(atPath: directory.path) else {
            return []
        }
        return try FileManager.default.contentsOfDirectory(atPath: directory.path)
    }

    private func makeInstaller(
        shell: ExtractingShellRunnerFake,
        installDirectory: URL? = nil
    ) -> StandaloneGitHubCLIInstaller {
        StandaloneGitHubCLIInstaller(
            shell: shell,
            architecture: "arm64",
            installDirectory: installDirectory ?? rootDirectory.appendingPathComponent("bin", isDirectory: true),
            temporaryDirectory: rootDirectory.appendingPathComponent("tmp", isDirectory: true)
        )
    }

    private func assertInstallFails(
        _ installer: StandaloneGitHubCLIInstaller,
        file: StaticString = #filePath,
        line: UInt = #line,
        assertMessage: (String) -> Void
    ) async {
        do {
            try await installer.install()
            XCTFail("Expected the install to fail.", file: file, line: line)
        } catch let error as OnboardingDependencyInstallError {
            assertMessage(error.message)
        } catch {
            XCTFail("Expected OnboardingDependencyInstallError, got \(error).", file: file, line: line)
        }
    }
}

/// Stands in for `curl`/`ditto`, materializing the extracted layout the real `ditto` would produce.
private actor ExtractingShellRunnerFake: ShellRunner {
    private let releaseTag: String
    private let architecture: String
    private let metadataBody: String?
    private let metadataExitCode: Int32
    private let downloadExitCode: Int32
    private let extractsExecutable: Bool
    private(set) var invocations: [MockShellRunner.Invocation] = []

    init(
        releaseTag: String,
        architecture: String,
        metadataBody: String? = nil,
        metadataExitCode: Int32 = 0,
        downloadExitCode: Int32 = 0,
        extractsExecutable: Bool = true
    ) {
        self.releaseTag = releaseTag
        self.architecture = architecture
        self.metadataBody = metadataBody
        self.metadataExitCode = metadataExitCode
        self.downloadExitCode = downloadExitCode
        self.extractsExecutable = extractsExecutable
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

        if executable == "/usr/bin/ditto" {
            return try extract(to: args[3])
        }
        if args.contains("-o") {
            return result(stdout: "", exitCode: downloadExitCode)
        }
        return result(
            stdout: metadataBody ?? #"{"tag_name":"\#(releaseTag)"}"#,
            exitCode: metadataExitCode
        )
    }

    private func extract(to destinationPath: String) throws -> ShellResult {
        guard extractsExecutable else {
            return result(stdout: "", exitCode: 0)
        }
        let version = releaseTag.hasPrefix("v") ? String(releaseTag.dropFirst()) : releaseTag
        let executableURL = URL(fileURLWithPath: destinationPath, isDirectory: true)
            .appendingPathComponent("gh_\(version)_macOS_\(architecture)", isDirectory: true)
            .appendingPathComponent("bin", isDirectory: true)
            .appendingPathComponent("gh")
        try FileManager.default.createDirectory(
            at: executableURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("#!/bin/sh\n".utf8).write(to: executableURL)
        return result(stdout: "", exitCode: 0)
    }

    private func result(stdout: String, exitCode: Int32) -> ShellResult {
        ShellResult(
            stdout: stdout,
            stderr: exitCode == 0 ? "" : "failed",
            exitCode: exitCode,
            stdoutWasTruncated: false,
            stderrWasTruncated: false
        )
    }
}
