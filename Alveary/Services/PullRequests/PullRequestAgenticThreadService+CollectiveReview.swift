import Foundation
import SwiftData

@MainActor
extension PullRequestAgenticThreadService {
    func startCollectiveReview(
        _ work: CollectiveReviewWork,
        coordinator: PullRequestReviewTeamCoordinator?
    ) async throws -> PullRequestAgenticThreadStart {
        guard let coordinator else {
            throw ReviewTeamError.invalidOutput("Review team is unavailable. Check Pull requests settings.")
        }
        let team = try await coordinator.preflight(settings: work.settings)
        guard let lead = team.first else {
            throw StartError.noReadyProvider
        }
        let seed = SeedSettings(
            provider: lead.providerID,
            model: lead.launchModel,
            effort: lead.effort,
            permissionMode: AppSettings.defaultPermissionMode(forProvider: lead.providerID)
        )
        let thread = try lifecycleService.insertTaskThread(seed: Self.threadSeed(
            seed,
            name: Kind.review.threadName(for: work.identifier),
            workspace: nil,
            workspaceSnapshot: nil,
            placement: resolvedPlacement(for: .review, settings: work.settings)
        ))
        guard let conversation = thread.soleMainConversation else {
            throw StartError.conversationMissing
        }
        let conversationID = conversation.id
        let threadID = thread.persistentModelID
        return PullRequestAgenticThreadStart(
            conversationID: conversationID,
            dispatch: Task { [linkService] in
                let linkFailure = await Self.collectiveReviewLinkFailure(
                    work,
                    threadID: threadID,
                    linkService: linkService
                )
                try coordinator.begin(
                    conversationID: conversationID,
                    identifier: work.identifier,
                    url: work.url,
                    team: team,
                    criteria: PullRequestReviewPromptBuilder.teamCriteria(settings: work.settings)
                )
                return PullRequestAgenticDispatchOutcome(linkFailure: linkFailure)
            }
        )
    }

    private static func collectiveReviewLinkFailure(
        _ work: CollectiveReviewWork,
        threadID: PersistentIdentifier,
        linkService: PullRequestLinkService
    ) async -> String? {
        do {
            _ = try await linkService.link(
                work.identifier,
                owner: .thread(threadID),
                detail: work.knownDetail,
                summary: work.knownSummary
            )
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
