import Foundation

/// The sheet snapshots settings for editing, but Save owns only the review lead and peers.
extension SettingsViewModel {
    /// Permissions are harness-scoped, so only a lead whose effective harness changes clears the review permission pin.
    func setPullRequestReviewTeam(_ draft: AppSettings) {
        settingsService.update { settings in
            if reviewTeamDraftLead(settings).harnessID != reviewTeamDraftLead(draft).harnessID {
                settings.pullRequestReviewPermissionMode = nil
            }
            settings.pullRequestReviewHarness = draft.pullRequestReviewHarness
            settings.pullRequestReviewModel = draft.pullRequestReviewModel
            settings.pullRequestReviewEffort = draft.pullRequestReviewEffort
            settings.pullRequestReviewPeers = draft.pullRequestReviewPeers
        }
    }

    func reviewTeamDraftLead(_ settings: AppSettings) -> PullRequestReviewPeer {
        let harnessID = settings.pullRequestReviewHarness ?? settings.defaultHarness
        let inheritsDefaults = harnessID == settings.defaultHarness
        return PullRequestReviewPeer(
            id: "lead",
            harnessID: harnessID,
            model: settings.pullRequestReviewModel
                ?? (inheritsDefaults ? settings.defaultModel : nil)
                ?? AppSettings.defaultModelValue,
            effort: settings.pullRequestReviewEffort
                ?? (inheritsDefaults ? settings.effort : harnessID == "opencode"
                    ? AppSettings.openCodeDefaultEffort : AppSettings.defaultEffortLevel)
        )
    }

    /// Inherits the stored Threads default strictly, as `PullRequestReviewTeamResolver` does, so an unready or
    /// non-concrete default reads on the button for repair rather than falling back.
    func reviewTeamLeadPresentation(_ draft: AppSettings) -> AgentReasoningPresentation {
        var inherited = draft
        inherited.pullRequestReviewHarness = nil
        inherited.pullRequestReviewModel = nil
        inherited.pullRequestReviewEffort = nil
        return AgentReasoningPresentation(
            harnesses: reviewTeamAgentHarnesses,
            pins: .init(harnessID: draft.pullRequestReviewHarness, model: draft.pullRequestReviewModel, effort: draft.pullRequestReviewEffort),
            effective: reviewTeamResolvedAgent(reviewTeamDraftLead(draft)),
            inheritance: .init(
                title: "Threads default",
                target: reviewTeamResolvedAgent(reviewTeamDraftLead(inherited)),
                isOffered: HarnessFeaturePolicy.supportsIsolatedReviewWorkers(harnessID: draft.defaultHarness)
            ),
            isChecking: isCheckingThreadDefaultHarnesses
        )
    }

    func applyReviewTeamLead(_ pins: AgentReasoningPins, in draft: inout AppSettings) -> Bool {
        draft.pullRequestReviewHarness = pins.harnessID
        draft.pullRequestReviewModel = pins.model
        draft.pullRequestReviewEffort = pins.effort
        return true
    }

    func reviewTeamPeerPresentation(_ peer: PullRequestReviewPeer) -> AgentReasoningPresentation {
        AgentReasoningPresentation(
            harnesses: reviewTeamAgentHarnesses,
            pins: .init(harnessID: peer.harnessID, model: peer.model, effort: peer.effort),
            effective: reviewTeamResolvedAgent(peer),
            isChecking: isCheckingThreadDefaultHarnesses
        )
    }

    /// Applies by `id` because removing a reviewer shifts every later index.
    func applyReviewTeamPeer(_ pins: AgentReasoningPins, id: String, in draft: inout AppSettings) -> Bool {
        guard let harnessID = pins.harnessID, let model = pins.model, let effort = pins.effort,
              let index = draft.pullRequestReviewPeers.firstIndex(where: { $0.id == id }) else {
            return false
        }
        draft.pullRequestReviewPeers[index].harnessID = harnessID
        draft.pullRequestReviewPeers[index].model = model
        draft.pullRequestReviewPeers[index].effort = effort
        return true
    }

    private var reviewTeamAgentHarnesses: [AgentReasoningPresentation.Harness] {
        threadDefaultHarnessIDs
            .filter { HarnessFeaturePolicy.supportsIsolatedReviewWorkers(harnessID: $0) }
            .map { reviewTeamAgentHarness(for: $0) }
    }

    private func reviewTeamResolvedAgent(_ worker: PullRequestReviewPeer) -> AgentReasoningPresentation.Resolved {
        AgentReasoningPresentation.Resolved(harness: reviewTeamAgentHarness(for: worker.harnessID), model: worker.model, effort: worker.effort)
    }
}
