import Foundation

extension DefaultOnboardingDependencyService {
    static let xcodeSelectExecutable = "/usr/bin/xcode-select"
    static let commandLineToolsProbeTimeout: Duration = .seconds(3)
    /// Deliberately shorter than `installerTimeout`. Apple's installer runs its own GUI, and
    /// `activeInstall` blocks every other row while this polls, so a stalled install must not
    /// hold the modal for the full installer window.
    static let commandLineToolsPollTimeout: Duration = .seconds(900)

    func commandLineToolsStatus() async -> OnboardingDependencyStatus {
        guard let developerDirectory = await resolvedDeveloperDirectory() else {
            return OnboardingDependencyStatus(dependency: .commandLineTools, state: .missing)
        }

        // Probe the git that `xcode-select` points at, never `/usr/bin/git`. The latter is the
        // shim, and running it is exactly what pops Apple's system-modal install dialog.
        let gitExecutable = URL(fileURLWithPath: developerDirectory, isDirectory: true)
            .appendingPathComponent("usr/bin/git")
            .path
        guard FileManager.default.isExecutableFile(atPath: gitExecutable),
              let versionResult = try? await shell.run(
                  executable: gitExecutable,
                  args: ["--version"],
                  timeout: Self.commandLineToolsProbeTimeout,
                  standardInput: .nullDevice
              ),
              versionResult.succeeded else {
            return OnboardingDependencyStatus(dependency: .commandLineTools, state: .missing)
        }

        let detail = versionResult.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return OnboardingDependencyStatus(
            dependency: .commandLineTools,
            state: .installed(detail: detail.isEmpty ? developerDirectory : detail)
        )
    }

    func installCommandLineTools() async throws -> OnboardingDependencyStatus {
        // A non-zero exit here also covers "already installed", which the poll below resolves.
        _ = try? await shell.run(
            executable: Self.xcodeSelectExecutable,
            args: ["--install"],
            timeout: Self.commandLineToolsProbeTimeout,
            standardInput: .nullDevice
        )

        let deadline = ContinuousClock.now.advanced(by: Self.commandLineToolsPollTimeout)
        while true {
            let status = await commandLineToolsStatus()
            if status.isInstalled {
                return status
            }
            try Task.checkCancellation()
            guard ContinuousClock.now < deadline else {
                throw OnboardingDependencyInstallError(
                    message: """
                    The Command Line Tools installer did not finish in time. \
                    Finish it in the macOS installer window, or run `xcode-select --install` in Terminal.
                    """
                )
            }
            try await Task.sleep(for: commandLineToolsPollInterval)
        }
    }

    private func resolvedDeveloperDirectory() async -> String? {
        guard let result = try? await shell.run(
            executable: Self.xcodeSelectExecutable,
            args: ["-p"],
            timeout: Self.commandLineToolsProbeTimeout,
            standardInput: .nullDevice
        ),
        result.succeeded else {
            return nil
        }

        let developerDirectory = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return developerDirectory.isEmpty ? nil : developerDirectory
    }
}
