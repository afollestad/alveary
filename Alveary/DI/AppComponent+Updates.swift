import Foundation

@MainActor
extension AppComponent {
    var appUpdateReleaseClient: any AppUpdateReleaseClient {
        return shared { GitHubCLIAppUpdateReleaseClient(shellRunner: shellRunner) }
    }

    var appVersionProvider: any AppVersionProviding {
        return shared { BundleAppVersionProvider() }
    }

    var appUpdateDownloader: any AppUpdateDownloading {
        return shared { GitHubCLIAppUpdateDownloader(shellRunner: shellRunner) }
    }

    var appUpdateStager: any AppUpdateStaging {
        return shared {
            DefaultAppUpdateStager(
                updatesDirectory: SessionComponent.appSupportDirectory.appendingPathComponent("Updates", isDirectory: true),
                shellRunner: shellRunner
            )
        }
    }

    var appUpdateInstaller: any AppUpdateInstalling {
        return shared {
            DefaultAppUpdateInstaller(
                updatesDirectory: SessionComponent.appSupportDirectory.appendingPathComponent("Updates", isDirectory: true),
                shellRunner: shellRunner
            )
        }
    }

    var appUpdateManager: AppUpdateManager {
        return shared {
            AppUpdateManager(
                releaseClient: appUpdateReleaseClient,
                versionProvider: appVersionProvider,
                downloader: appUpdateDownloader,
                stager: appUpdateStager,
                installer: appUpdateInstaller
            )
        }
    }
}
