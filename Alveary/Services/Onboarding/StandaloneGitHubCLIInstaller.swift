import Foundation

@MainActor
protocol StandaloneGitHubCLIInstalling: AnyObject, Sendable {
    func install() async throws
}

/// Installs the official precompiled `gh` release into `~/.local/bin`.
///
/// This is the path for machines without Homebrew. Bootstrapping Homebrew is not an option here:
/// its installer needs `sudo`, and onboarding installers deliberately run with null stdin, so the
/// prompt can only abort. The release tarball needs no `sudo`, no Command Line Tools, and lands in
/// a directory `ExecutablePathResolver` already searches.
@MainActor
final class StandaloneGitHubCLIInstaller: StandaloneGitHubCLIInstalling {
    static let manualInstallGuidance = "Install it manually from https://cli.github.com."

    private static let latestReleaseURL = "https://api.github.com/repos/cli/cli/releases/latest"
    private static let downloadURLPrefix = "https://github.com/cli/cli/releases/download"
    private static let metadataTimeout: Duration = .seconds(30)
    private static let downloadTimeout: Duration = .seconds(600)
    private static let extractTimeout: Duration = .seconds(120)
    private static let metadataLimitBytes = 256 * 1024
    private static let outputLimitBytes = 128 * 1024

    private let shell: ShellRunner
    private let fileManager: FileManager
    private let architecture: String
    private let installDirectory: URL
    private let temporaryDirectory: URL

    init(
        shell: ShellRunner,
        fileManager: FileManager = .default,
        architecture: String = StandaloneGitHubCLIInstaller.hostArchitecture,
        installDirectory: URL? = nil,
        temporaryDirectory: URL? = nil
    ) {
        self.shell = shell
        self.fileManager = fileManager
        self.architecture = architecture
        self.installDirectory = installDirectory
            ?? URL(fileURLWithPath: ExecutableSearchPath.expandHomeDirectory(in: "~/.local/bin"), isDirectory: true)
        self.temporaryDirectory = temporaryDirectory ?? fileManager.temporaryDirectory
    }

    nonisolated static var hostArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #else
        return "amd64"
        #endif
    }

    func install() async throws {
        let tag = try await latestReleaseTag()
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        guard !version.isEmpty else {
            throw failure("Could not read the latest GitHub CLI version.")
        }

        let workingDirectory = temporaryDirectory
            .appendingPathComponent("AlvearyGitHubCLIInstall", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? fileManager.removeItem(at: workingDirectory) }

        do {
            try fileManager.createDirectory(at: workingDirectory, withIntermediateDirectories: true)
        } catch {
            throw failure("Could not create a temporary directory for the GitHub CLI download.")
        }

        let archiveName = "gh_\(version)_macOS_\(architecture)"
        let archiveURL = workingDirectory.appendingPathComponent("\(archiveName).zip")
        let extractDirectory = workingDirectory.appendingPathComponent("extract", isDirectory: true)

        try await download(
            from: "\(Self.downloadURLPrefix)/\(tag)/\(archiveName).zip",
            to: archiveURL
        )
        try await extract(archiveURL: archiveURL, to: extractDirectory)
        try copyExecutable(
            from: extractDirectory
                .appendingPathComponent(archiveName, isDirectory: true)
                .appendingPathComponent("bin", isDirectory: true)
                .appendingPathComponent("gh")
        )
    }

    private func latestReleaseTag() async throws -> String {
        let result = try await run(
            executable: "/usr/bin/curl",
            args: ["-fsSL", Self.latestReleaseURL],
            timeout: Self.metadataTimeout,
            stdoutLimitBytes: Self.metadataLimitBytes,
            // A failed `curl` here is the offline case, and it must not read as a broken install.
            unreachableMessage: "Could not reach GitHub to look up the latest GitHub CLI release."
        )

        guard let metadata = try? JSONDecoder().decode(ReleaseMetadata.self, from: Data(result.stdout.utf8)),
              !metadata.tagName.isEmpty else {
            throw failure("GitHub returned an unexpected response for the latest GitHub CLI release.")
        }
        return metadata.tagName
    }

    private func download(from urlString: String, to destination: URL) async throws {
        _ = try await run(
            executable: "/usr/bin/curl",
            args: ["-fsSL", "-o", destination.path, urlString],
            timeout: Self.downloadTimeout,
            stdoutLimitBytes: Self.outputLimitBytes,
            unreachableMessage: "Could not download the GitHub CLI."
        )
    }

    private func extract(archiveURL: URL, to destination: URL) async throws {
        // `ditto` ships with macOS itself, unlike `unzip -o` behavior differences across versions.
        _ = try await run(
            executable: "/usr/bin/ditto",
            args: ["-x", "-k", archiveURL.path, destination.path],
            timeout: Self.extractTimeout,
            stdoutLimitBytes: Self.outputLimitBytes,
            unreachableMessage: "Could not unpack the GitHub CLI download."
        )
    }

    private func copyExecutable(from sourceURL: URL) throws {
        guard fileManager.isReadableFile(atPath: sourceURL.path) else {
            throw failure("The GitHub CLI download did not contain the expected `gh` executable.")
        }

        let destinationURL = installDirectory.appendingPathComponent("gh")
        do {
            try fileManager.createDirectory(at: installDirectory, withIntermediateDirectories: true)
            if fileManager.fileExists(atPath: destinationURL.path) {
                try fileManager.removeItem(at: destinationURL)
            }
            try fileManager.copyItem(at: sourceURL, to: destinationURL)
            try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        } catch {
            throw failure("Could not install the GitHub CLI into \(installDirectory.path).")
        }
    }

    private func run(
        executable: String,
        args: [String],
        timeout: Duration,
        stdoutLimitBytes: Int,
        unreachableMessage: String
    ) async throws -> ShellResult {
        let result: ShellResult
        do {
            result = try await shell.run(
                executable: executable,
                args: args,
                timeout: timeout,
                stdoutLimitBytes: stdoutLimitBytes,
                stderrLimitBytes: Self.outputLimitBytes,
                standardInput: .nullDevice
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw failure(unreachableMessage)
        }

        guard result.succeeded else {
            throw failure(unreachableMessage)
        }
        return result
    }

    private func failure(_ message: String) -> OnboardingDependencyInstallError {
        OnboardingDependencyInstallError(message: "\(message) \(Self.manualInstallGuidance)")
    }
}

private struct ReleaseMetadata: Decodable {
    let tagName: String

    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
    }
}
