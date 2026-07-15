import AppKit
import Foundation

struct DefaultAppUpdateInstaller: AppUpdateInstalling, @unchecked Sendable {
    private let updatesDirectory: URL
    private let storagePaths: AppUpdateStoragePaths
    private let shellRunner: any ShellRunner
    private let fileManager: FileManager
    private let bundle: Bundle
    private let processIdentifier: @Sendable () -> Int32
    private let terminateApp: @Sendable () -> Void
    private let helperScript: AppUpdateInstallHelperScript

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
        },
        helperScript: AppUpdateInstallHelperScript = .live
    ) {
        self.updatesDirectory = updatesDirectory
        self.storagePaths = AppUpdateStoragePaths(updatesDirectory: updatesDirectory)
        self.shellRunner = shellRunner
        self.fileManager = fileManager
        self.bundle = bundle
        self.processIdentifier = processIdentifier
        self.terminateApp = terminateApp
        self.helperScript = helperScript
    }

    func installAndRelaunch(stagedUpdate: StagedAppUpdate) async throws {
        let currentBundleURL = try currentInstallBundleURL()
        let stagedDirectory = try await verifyInstallInputs(
            currentBundleURL: currentBundleURL,
            stagedUpdate: stagedUpdate
        )

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
        let quarantinedMetadataURL = storagePaths.quarantinedMetadataURL(id: UUID())

        try helperScript.contents.write(to: helperURL, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [helperURL.path] + helperScript.arguments(
            for: AppUpdateInstallHelperInvocation(
                runningProcessIdentifier: processIdentifier(),
                stagedAppURL: stagedUpdate.appBundleURL,
                stagedDirectoryURL: stagedDirectory,
                targetAppURL: currentBundleURL,
                backupAppURL: backupURL,
                logURL: logURL,
                metadataURL: storagePaths.metadataURL,
                quarantinedMetadataURL: quarantinedMetadataURL,
                helperURL: helperURL
            )
        )
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

    func verifyInstallInputs(currentBundleURL: URL, stagedUpdate: StagedAppUpdate) async throws -> URL {
        try storagePaths.validateMetadataURL(stagedUpdate.metadataURL)
        let stagedDirectory = try storagePaths.validatedStagedDirectory(containing: stagedUpdate.appBundleURL)

        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: stagedUpdate.appBundleURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw AppUpdateFailure(message: "The staged update is no longer available.")
        }
        guard fileManager.fileExists(atPath: storagePaths.metadataURL.path) else {
            throw AppUpdateFailure(message: "The staged update metadata is no longer available.")
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
        return stagedDirectory
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

}

struct AppUpdateInstallHelperScript: Sendable {
    static let live = AppUpdateInstallHelperScript(
        copyExecutableURL: URL(fileURLWithPath: "/usr/bin/ditto"),
        openExecutableURL: URL(fileURLWithPath: "/usr/bin/open"),
        relaunchGraceSeconds: 3
    )

    let copyExecutableURL: URL
    let openExecutableURL: URL
    let relaunchGraceSeconds: TimeInterval

    func arguments(for invocation: AppUpdateInstallHelperInvocation) -> [String] {
        [
            "\(invocation.runningProcessIdentifier)",
            invocation.stagedAppURL.path,
            invocation.stagedDirectoryURL.path,
            invocation.targetAppURL.path,
            invocation.backupAppURL.path,
            invocation.logURL.path,
            invocation.metadataURL.path,
            invocation.quarantinedMetadataURL.path,
            invocation.helperURL.path,
            copyExecutableURL.path,
            openExecutableURL.path,
            "\(relaunchGraceSeconds)"
        ]
    }

    var contents: String {
        #"""
        set -u

        RUNNING_PID="$1"
        STAGED_APP="$2"
        STAGED_DIRECTORY="$3"
        TARGET_APP="$4"
        BACKUP_APP="$5"
        LOG_FILE="$6"
        METADATA_FILE="$7"
        QUARANTINED_METADATA_FILE="$8"
        HELPER_FILE="$9"
        COPY_EXECUTABLE="${10}"
        OPEN_EXECUTABLE="${11}"
        GRACE_SECONDS="${12}"

        exec >>"$LOG_FILE" 2>&1
        echo "Starting Alveary update install at $(date)"

        reopen_target() {
          if [ -e "$TARGET_APP" ]; then
            "$OPEN_EXECUTABLE" "$TARGET_APP" || true
          fi
        }

        restore_metadata() {
          if [ -e "$QUARANTINED_METADATA_FILE" ]; then
            mv "$QUARANTINED_METADATA_FILE" "$METADATA_FILE"
          fi
        }

        restore_backup() {
          rm -rf "$TARGET_APP"
          if [ -e "$BACKUP_APP" ]; then
            mv "$BACKUP_APP" "$TARGET_APP"
          fi
        }

        rollback() {
          echo "$1"
          restore_backup || true
          restore_metadata || true
          reopen_target
          exit 1
        }

        while kill -0 "$RUNNING_PID" 2>/dev/null; do
          sleep 0.2
        done

        if ! rm -rf "$BACKUP_APP"; then
          echo "Could not clear the update backup path"
          reopen_target
          exit 1
        fi

        if ! mv "$METADATA_FILE" "$QUARANTINED_METADATA_FILE"; then
          echo "Could not quarantine staged update metadata"
          reopen_target
          exit 1
        fi

        if [ -e "$TARGET_APP" ] && ! mv "$TARGET_APP" "$BACKUP_APP"; then
          echo "Could not move the installed app to its backup path"
          restore_metadata || true
          reopen_target
          exit 1
        fi

        if ! "$COPY_EXECUTABLE" "$STAGED_APP" "$TARGET_APP"; then
          rollback "Failed to copy staged app; restoring backup"
        fi

        if ! "$OPEN_EXECUTABLE" "$TARGET_APP"; then
          rollback "Failed to relaunch updated app; restoring backup"
        fi

        sleep "$GRACE_SECONDS"
        rm -rf "$BACKUP_APP"
        rm -f "$QUARANTINED_METADATA_FILE"
        rm -rf "$STAGED_DIRECTORY"
        rm -f "$HELPER_FILE"
        echo "Alveary update install completed at $(date)"
        exit 0
        """#
    }
}

struct AppUpdateInstallHelperInvocation: Sendable {
    let runningProcessIdentifier: Int32
    let stagedAppURL: URL
    let stagedDirectoryURL: URL
    let targetAppURL: URL
    let backupAppURL: URL
    let logURL: URL
    let metadataURL: URL
    let quarantinedMetadataURL: URL
    let helperURL: URL
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
