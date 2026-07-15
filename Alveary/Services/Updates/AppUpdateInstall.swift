import Foundation

struct AppUpdateFailure: Equatable, Sendable, LocalizedError {
    let message: String

    var errorDescription: String? {
        message
    }

    static func from(_ error: any Error) -> AppUpdateFailure {
        if let failure = error as? AppUpdateFailure {
            return failure
        }

        return AppUpdateFailure(message: error.localizedDescription)
    }
}

struct StagedAppUpdate: Equatable, Identifiable, Sendable {
    var id: String {
        release.tagName
    }

    let release: AppUpdateRelease
    let appBundleURL: URL
    let metadataURL: URL
    let stagedAt: Date
}

enum AppUpdateDownloadState: Equatable, Sendable {
    case idle
    case checkingLatestRelease
    case downloading(AppUpdateRelease, progress: Double)
    case staging(AppUpdateRelease)
    case readyToInstall(StagedAppUpdate)
    case installing(StagedAppUpdate)
    case failed(AppUpdateFailure)
}

protocol AppUpdateDownloading: Sendable {
    func download(
        release: AppUpdateRelease,
        progress: @escaping @Sendable (Double) async -> Void
    ) async throws -> URL
}

protocol AppUpdateStaging: Sendable {
    func stageDownloadedUpdate(
        release: AppUpdateRelease,
        downloadedZIPURL: URL
    ) async throws -> StagedAppUpdate

    func loadValidatedStagedUpdate() async throws -> StagedAppUpdate?
}

protocol AppUpdateInstalling: Sendable {
    func installAndRelaunch(stagedUpdate: StagedAppUpdate) async throws
}

struct AppUpdateStoragePaths: Sendable {
    let updatesDirectory: URL

    var metadataURL: URL {
        updatesDirectory.appendingPathComponent("staged-update.json")
    }

    var stagedRootURL: URL {
        updatesDirectory.appendingPathComponent("Staged", isDirectory: true)
    }

    func quarantinedMetadataURL(id: UUID) -> URL {
        updatesDirectory
            .appendingPathComponent("staged-update.installing-\(id.uuidString)")
            .appendingPathExtension("json")
    }

    func stagedAppURL(directoryName: String) throws -> URL {
        let appURL = stagedRootURL
            .appendingPathComponent(directoryName, isDirectory: true)
            .appendingPathComponent("Alveary.app", isDirectory: true)
        _ = try validatedStagedDirectory(containing: appURL)
        return appURL
    }

    func validateMetadataURL(_ candidateURL: URL) throws {
        guard candidateURL.isFileURL,
              candidateURL.standardizedFileURL == metadataURL.standardizedFileURL else {
            throw AppUpdateFailure(message: "The staged update metadata is outside Alveary's update storage.")
        }
    }

    // Cleanup callers may delete only the exact single-child directory returned after these symlink checks.
    func validatedStagedDirectory(containing appBundleURL: URL) throws -> URL {
        let standardizedRoot = stagedRootURL.standardizedFileURL
        let standardizedApp = appBundleURL.standardizedFileURL
        let standardizedDirectory = standardizedApp.deletingLastPathComponent()
        let directoryName = standardizedDirectory.lastPathComponent
        let pathComponents = appBundleURL.pathComponents

        guard appBundleURL.isFileURL,
              !pathComponents.contains("."),
              !pathComponents.contains(".."),
              standardizedApp.lastPathComponent == "Alveary.app",
              !directoryName.isEmpty,
              directoryName != ".",
              directoryName != "..",
              standardizedDirectory.deletingLastPathComponent() == standardizedRoot else {
            throw AppUpdateFailure(message: "The staged app is outside Alveary's update storage.")
        }

        let resolvedUpdatesDirectory = updatesDirectory.standardizedFileURL.resolvingSymlinksInPath()
        let resolvedRoot = standardizedRoot.resolvingSymlinksInPath()
        let resolvedDirectory = standardizedDirectory.resolvingSymlinksInPath()
        let resolvedApp = standardizedApp.resolvingSymlinksInPath()
        guard resolvedRoot.deletingLastPathComponent().path == resolvedUpdatesDirectory.path,
              resolvedRoot.lastPathComponent == "Staged",
              resolvedDirectory.deletingLastPathComponent().path == resolvedRoot.path,
              resolvedDirectory.lastPathComponent == directoryName,
              resolvedApp.deletingLastPathComponent().path == resolvedDirectory.path,
              resolvedApp.lastPathComponent == "Alveary.app" else {
            throw AppUpdateFailure(message: "The staged app is outside Alveary's update storage.")
        }

        return standardizedDirectory
    }
}
