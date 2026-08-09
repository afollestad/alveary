import Foundation

@MainActor
extension AppComponent {
    /// App-scoped pull-request linking. `PullRequestLinksViewModel` is per-window and builds its
    /// own over the same `mainContext`; the `alveary_host` thread tools use this one.
    var pullRequestLinkService: PullRequestLinkService {
        return shared {
            PullRequestLinkService(
                modelContext: modelContainer.mainContext,
                service: pullRequestsService
            )
        }
    }

    /// Starts the pull request pane's agentic threads. App-scoped alongside the thread tools it
    /// shares a spawn path with; the pane's view model reaches it through a closure.
    var pullRequestAgenticThreadService: PullRequestAgenticThreadService {
        return shared {
            PullRequestAgenticThreadService(
                lifecycleService: threadLifecycleService,
                linkService: pullRequestLinkService,
                pullRequestsService: pullRequestsService,
                settingsService: settingsService,
                worktreeManager: worktreeManager,
                taskWorkspaceOwnershipService: taskWorkspaceOwnershipService,
                providerDiscovery: cachedAgentProviderDiscoveryService,
                startInitialPrompt: { conversation, prompt in
                    self.startHeadlessInitialPrompt(conversation: conversation, prompt: prompt)
                }
            )
        }
    }

    /// The `alveary_host` pull request tools. App-scoped so its pending-review serialization spans
    /// every conversation that can reach GitHub.
    var pullRequestHostToolService: PullRequestHostToolService {
        return shared {
            PullRequestHostToolService(
                modelContext: modelContainer.mainContext,
                pullRequestsService: pullRequestsService,
                settingsService: settingsService
            )
        }
    }

    var pullRequestsService: any PullRequestsService {
        return shared {
            demoPullRequestsService ?? GitHubPullRequestsService(
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
