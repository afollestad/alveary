import Foundation

/// The sheet snapshots settings for editing, but Save owns only the review lead and peers.
extension SettingsViewModel {
    func setPullRequestReviewTeam(_ draft: AppSettings) {
        settingsService.update { settings in
            if settings.pullRequestReviewHarness != draft.pullRequestReviewHarness {
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
                ?? (inheritsDefaults ? settings.effort : AppSettings.defaultEffortLevel)
        )
    }

    func reviewTeamLeadHarnessOptions(_ settings: AppSettings) -> [String] {
        [Self.pullRequestReviewInheritValue]
            + pullRequestReviewPeerHarnessOptions(including: reviewTeamDraftLead(settings).harnessID)
    }

    func reviewTeamLeadModelOptions(_ settings: AppSettings) -> [String] {
        [Self.pullRequestReviewInheritValue] + pullRequestReviewPeerModelOptions(reviewTeamDraftLead(settings))
    }

    func reviewTeamLeadModelSelection(_ settings: AppSettings) -> String {
        guard settings.pullRequestReviewModel != nil else { return Self.pullRequestReviewInheritValue }
        return pullRequestReviewPeerModelSelection(reviewTeamDraftLead(settings))
    }

    func reviewTeamLeadEffortOptions(_ settings: AppSettings) -> [String] {
        [Self.pullRequestReviewInheritValue] + pullRequestReviewPeerEffortOptions(reviewTeamDraftLead(settings))
    }

    func reviewTeamLeadHarnessLabel(_ value: String, settings: AppSettings) -> String {
        value == Self.pullRequestReviewInheritValue
            ? "Default (\(harnessDisplayName(for: settings.defaultHarness)))"
            : harnessDisplayName(for: value)
    }

    func reviewTeamLeadModelLabel(_ value: String, settings: AppSettings) -> String {
        var inherited = settings
        inherited.pullRequestReviewModel = nil
        let lead = reviewTeamDraftLead(value == Self.pullRequestReviewInheritValue ? inherited : settings)
        let label = pullRequestReviewPeerModelLabel(
            value == Self.pullRequestReviewInheritValue ? lead.model : value,
            harnessID: lead.harnessID
        )
        return value == Self.pullRequestReviewInheritValue ? "Default (\(label))" : label
    }

    func reviewTeamLeadEffortLabel(_ value: String, settings: AppSettings) -> String {
        var inherited = settings
        inherited.pullRequestReviewEffort = nil
        let lead = reviewTeamDraftLead(value == Self.pullRequestReviewInheritValue ? inherited : settings)
        let label = pullRequestReviewPeerEffortLabel(value == Self.pullRequestReviewInheritValue ? lead.effort : value, peer: lead)
        return value == Self.pullRequestReviewInheritValue ? "Default (\(label))" : label
    }

    func setReviewTeamLeadHarness(_ value: String, in settings: inout AppSettings) {
        settings.pullRequestReviewHarness = value == Self.pullRequestReviewInheritValue ? nil : value
        settings.pullRequestReviewModel = nil
        settings.pullRequestReviewEffort = nil
    }

    func setReviewTeamLeadModel(_ value: String, in settings: inout AppSettings) {
        if value == Self.pullRequestReviewInheritValue {
            settings.pullRequestReviewModel = nil
            settings.pullRequestReviewEffort = nil
        } else {
            let harnessID = reviewTeamDraftLead(settings).harnessID
            let model = pullRequestReviewPeerStoredModel(harnessID: harnessID, selection: value)
            settings.pullRequestReviewModel = model
            settings.pullRequestReviewEffort = pullRequestReviewPeerDefaultEffort(harnessID: harnessID, model: model)
        }
    }
}
