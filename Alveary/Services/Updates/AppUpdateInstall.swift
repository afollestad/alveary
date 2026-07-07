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
