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
                currentBranch: { [gitService] path in
                    try? await gitService.currentBranch(in: path)
                },
                startInitialPrompt: { conversation, prompt in
                    self.startHeadlessInitialPrompt(conversation: conversation, prompt: prompt)
                }
            )
        }
    }

    /// Which agentic pull-request routes are running. App-scoped alongside the service that starts
    /// them: the detail pane unmounts whenever the user looks elsewhere, so a per-window or
    /// per-session owner would forget a run the moment it stopped being watched.
    var pullRequestAgenticThreadActivity: PullRequestAgenticThreadActivity {
        return shared {
            PullRequestAgenticThreadActivity(
                currentSignal: { [agentsManager] conversationID in
                    agentsManager.status(for: conversationID)
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
                settingsService: settingsService,
                summaryHandoff: pullRequestSummaryHandoff,
                reviewProposalPreviewCache: pullRequestReviewProposalPreviewCache
            )
        }
    }

    /// Hands `list_involved_prs` rows to `link_pr`, whose link then skips its validating fetch.
    /// App-scoped because the writer is the pull request tools and the reader the thread tools;
    /// hand both the same instance, or the reader consults an always-empty store.
    var pullRequestSummaryHandoff: PullRequestSummaryHandoff {
        return shared { PullRequestSummaryHandoff() }
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

    /// App-scoped so the `gh auth token` read and its cache are shared by every pane, rather than
    /// each pull request spawning its own `gh` on the first image it draws.
    var gitHubDiffImageBlobFetcher: GitHubDiffImageBlobFetcher {
        return shared {
            GitHubDiffImageBlobFetcher(
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

    /// App-scoped because propose time writes it and the transcript's proposal coordinator reads it;
    /// two instances would leave the card loading from a cache nothing ever filled.
    var pullRequestReviewProposalPreviewCache: PullRequestReviewProposalPreviewCache {
        return shared {
            PullRequestReviewProposalPreviewCache(
                fileURL: storageProfile.reviewProposalPreviewCacheFileURL
            )
        }
    }
}
