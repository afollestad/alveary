import AppKit
import Foundation

struct DefaultAppUpdateInstaller: AppUpdateInstalling, @unchecked Sendable {
    private let updatesDirectory: URL
    private let shellRunner: any ShellRunner
    private let fileManager: FileManager
    private let bundle: Bundle
    private let processIdentifier: @Sendable () -> Int32
    private let terminateApp: @Sendable () -> Void

    init(
        updatesDirectory: URL,
        shellRunner: any ShellRunner,
        fileManager: FileManager = .default,
        bundle: Bundle = .main,
        processIdentifier: @escaping @Sendable () -> Int32 = { ProcessInfo.processInfo.processIdentifier },
        terminateApp: @escaping @Sendable () -> Void = {
            Task { @MainActor in
                NSApplication.shared.terminate(nil)
            }
        }
    ) {
        self.updatesDirectory = updatesDirectory
        self.shellRunner = shellRunner
        self.fileManager = fileManager
        self.bundle = bundle
        self.processIdentifier = processIdentifier
        self.terminateApp = terminateApp
    }

    func installAndRelaunch(stagedUpdate: StagedAppUpdate) async throws {
        let currentBundleURL = try currentInstallBundleURL()
        try await verifyInstallInputs(currentBundleURL: currentBundleURL, stagedUpdate: stagedUpdate)

        let helpersDirectory = updatesDirectory.appendingPathComponent("Helpers", isDirectory: true)
        let logsDirectory = updatesDirectory.appendingPathComponent("Logs", isDirectory: true)
        try fileManager.createDirectory(
            at: helpersDirectory,
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )

        let helperURL = helpersDirectory
            .appendingPathComponent("install-\(UUID().uuidString)")
            .appendingPathExtension("zsh")
        let logURL = logsDirectory
            .appendingPathComponent("install-\(stagedUpdate.release.tagName.sanitizedForShellFileName)-\(UUID().uuidString)")
            .appendingPathExtension("log")
        let backupURL = currentBundleURL
            .deletingLastPathComponent()
            .appendingPathComponent(".Alveary.app.backup-\(UUID().uuidString)", isDirectory: true)

        try helperScript.write(to: helperURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [
            helperURL.path,
            "\(processIdentifier())",
            stagedUpdate.appBundleURL.path,
            currentBundleURL.path,
            backupURL.path,
            logURL.path,
            stagedUpdate.metadataURL.path,
            helperURL.path
        ]
        try process.run()

        terminateApp()
    }
}

private extension DefaultAppUpdateInstaller {
    func currentInstallBundleURL() throws -> URL {
        let currentBundleURL = bundle.bundleURL.standardizedFileURL
        guard currentBundleURL.pathExtension == "app" else {
            throw AppUpdateFailure(message: "Alveary is not running from an app bundle.")
        }
        guard !currentBundleURL.path.contains("/AppTranslocation/") else {
            throw AppUpdateFailure(message: "Move Alveary out of the translocated disk image before installing updates.")
        }
        guard !currentBundleURL.path.isDevelopmentBuildPath else {
            throw AppUpdateFailure(message: "Updates cannot be installed over a development build.")
        }

        let parentDirectory = currentBundleURL.deletingLastPathComponent()
        guard fileManager.isWritableFile(atPath: parentDirectory.path) else {
            throw AppUpdateFailure(message: "Alveary's install location is not writable.")
        }
        return currentBundleURL
    }

    func verifyInstallInputs(currentBundleURL: URL, stagedUpdate: StagedAppUpdate) async throws {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: stagedUpdate.appBundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AppUpdateFailure(message: "The staged update is no longer available.")
        }

        try await runRequired(
            executable: "/usr/bin/codesign",
            args: ["--verify", "--deep", "--strict", "--verbose=2", currentBundleURL.path],
            failureMessage: "The running app is not signed correctly."
        )
        try await runRequired(
            executable: "/usr/bin/codesign",
            args: ["--verify", "--deep", "--strict", "--verbose=2", stagedUpdate.appBundleURL.path],
            failureMessage: "The staged update is not signed correctly."
        )
    }

    func runRequired(
        executable: String,
        args: [String],
        failureMessage: String
    ) async throws {
        let result = try await shellRunner.run(
            executable: executable,
            args: args,
            timeout: .seconds(60),
            stdoutLimitBytes: 64 * 1024,
            stderrLimitBytes: 64 * 1024
        )
        guard result.succeeded else {
            let detail = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw AppUpdateFailure(message: detail.isEmpty ? failureMessage : "\(failureMessage) \(detail)")
        }
    }

    var helperScript: String {
        #"""
        set -u

        RUNNING_PID="$1"
        STAGED_APP="$2"
        TARGET_APP="$3"
        BACKUP_APP="$4"
        LOG_FILE="$5"
        METADATA_FILE="$6"
        HELPER_FILE="$7"

        exec >>"$LOG_FILE" 2>&1
        echo "Starting Alveary update install at $(date)"

        while kill -0 "$RUNNING_PID" 2>/dev/null; do
          sleep 0.2
        done

        rm -rf "$BACKUP_APP"

        if [ -e "$TARGET_APP" ]; then
          mv "$TARGET_APP" "$BACKUP_APP"
        fi

        if /usr/bin/ditto "$STAGED_APP" "$TARGET_APP"; then
          /usr/bin/open "$TARGET_APP"
          sleep 3
          rm -rf "$BACKUP_APP"
          rm -f "$METADATA_FILE"
          rm -rf "$(dirname "$STAGED_APP")"
          rm -f "$HELPER_FILE"
          echo "Alveary update install completed at $(date)"
          exit 0
        fi

        echo "Failed to copy staged app; restoring backup"
        rm -rf "$TARGET_APP"
        if [ -e "$BACKUP_APP" ]; then
          mv "$BACKUP_APP" "$TARGET_APP"
          /usr/bin/open "$TARGET_APP"
        fi
        exit 1
        """#
    }
}

private extension String {
    var sanitizedForShellFileName: String {
        components(separatedBy: CharacterSet.alphanumerics.union(CharacterSet(charactersIn: ".-_")).inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
    }

    var isDevelopmentBuildPath: Bool {
        contains("/DerivedData/")
            || contains("/Build/Products/")
            || contains("/.build/")
    }
}
