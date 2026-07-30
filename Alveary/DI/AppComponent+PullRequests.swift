import Foundation

@MainActor
extension AppComponent {
    var pullRequestsService: any PullRequestsService {
        return shared {
            GitHubPullRequestsService(
                shellRunner: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }

    var gitHubAttachmentUploadService: any GitHubAttachmentUploadService {
        return shared {
            DefaultGitHubAttachmentUploadService(
                shellRunner: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }

    var gitHubAttachmentImageURLResolver: GitHubAttachmentImageURLResolver {
        return shared {
            GitHubAttachmentImageURLResolver(
                shellRunner: shellRunner,
                executableResolver: executablePathResolver
            )
        }
    }

    var gitHubAvatarLoader: GitHubAvatarLoader {
        return shared { GitHubAvatarLoader() }
    }

    var pullRequestsListCache: PullRequestsListCache {
        return shared { PullRequestsListCache(fileURL: storageProfile.pullRequestsListCacheFileURL) }
    }
}
