import Foundation

@MainActor
extension AppComponent {
    var reviewPacketStore: ReviewPacketStore {
        return shared {
            ReviewPacketStore(rootDirectory: storageProfile.appSupportDirectory.appendingPathComponent("ReviewPackets"))
        }
    }

    var pullRequestReviewWorkerProcessRegistry: PullRequestReviewWorkerProcessRegistry {
        return shared { PullRequestReviewWorkerProcessRegistry() }
    }

    var reviewTeamHistoryStore: ReviewTeamHistoryStore {
        return shared {
            ReviewTeamHistoryStore(rootDirectory: storageProfile.appSupportDirectory.appendingPathComponent("ReviewHistory"))
        }
    }

    var pullRequestReviewWorkerExecutor: DefaultPullRequestReviewWorkerExecutor {
        return shared {
            DefaultPullRequestReviewWorkerExecutor(
                environmentBuilder: agentEnvironmentBuilder,
                processRegistry: pullRequestReviewWorkerProcessRegistry
            )
        }
    }

    var collectiveReviewStagingService: PullRequestCollectiveReviewStagingService {
        return shared {
            PullRequestCollectiveReviewStagingService(
                modelContext: modelContainer.mainContext, service: pullRequestsService,
                previewCache: pullRequestReviewProposalPreviewCache
            )
        }
    }

    var pullRequestReviewTeamCoordinator: PullRequestReviewTeamCoordinator {
        return shared {
            PullRequestReviewTeamCoordinator(
                modelContext: modelContainer.mainContext, service: pullRequestsService,
                worker: pullRequestReviewWorkerExecutor, packets: reviewPacketStore,
                staging: collectiveReviewStagingService, activity: pullRequestAgenticThreadActivity,
                resolver: PullRequestReviewTeamResolver(providerDiscovery: cachedAgentProviderDiscoveryService),
                cancellationStore: ReviewTeamCancellationStore(
                    rootDirectory: storageProfile.appSupportDirectory.appendingPathComponent("ReviewCancellations")
                ),
                historyStore: reviewTeamHistoryStore
            )
        }
    }

    func prepareReviewTeamForTermination() {
        pullRequestReviewTeamCoordinator.prepareForTermination()
        pullRequestReviewWorkerProcessRegistry.terminateAllSynchronously()
    }
}
