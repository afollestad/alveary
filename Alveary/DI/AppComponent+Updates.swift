import Foundation

@MainActor
extension AppComponent {
    var appUpdateReleaseClient: any AppUpdateReleaseClient {
        return shared {
            GitHubCLIAppUpdateReleaseClient(
                shellRunner: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }

    var appVersionProvider: any AppVersionProviding {
        return shared { BundleAppVersionProvider() }
    }

    var appUpdateDownloader: any AppUpdateDownloading {
        return shared {
            GitHubCLIAppUpdateDownloader(
                shellRunner: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }

    var appUpdateStager: any AppUpdateStaging {
        return shared {
            DefaultAppUpdateStager(
                updatesDirectory: storageProfile.updatesDirectory,
                shellRunner: shellRunner
            )
        }
    }

    var appUpdateInstaller: any AppUpdateInstalling {
        return shared {
            DefaultAppUpdateInstaller(
                updatesDirectory: storageProfile.updatesDirectory,
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
