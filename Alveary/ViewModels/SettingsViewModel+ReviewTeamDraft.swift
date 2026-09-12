import Foundation

/// The sheet snapshots settings for editing, but Save owns only the review lead and peers.
extension SettingsViewModel {
    func setPullRequestReviewTeam(_ draft: AppSettings) {
        settingsService.update { settings in
            if settings.pullRequestReviewProvider != draft.pullRequestReviewProvider {
                settings.pullRequestReviewPermissionMode = nil
            }
            settings.pullRequestReviewProvider = draft.pullRequestReviewProvider
            settings.pullRequestReviewModel = draft.pullRequestReviewModel
            settings.pullRequestReviewEffort = draft.pullRequestReviewEffort
            settings.pullRequestReviewPeers = draft.pullRequestReviewPeers
        }
    }

    func reviewTeamDraftLead(_ settings: AppSettings) -> PullRequestReviewPeer {
        let providerID = settings.pullRequestReviewProvider ?? settings.defaultProvider
        let inheritsDefaults = providerID == settings.defaultProvider
        return PullRequestReviewPeer(
            id: "lead",
            providerID: providerID,
            model: settings.pullRequestReviewModel
                ?? (inheritsDefaults ? settings.defaultModel : nil)
                ?? AppSettings.defaultModelValue,
            effort: settings.pullRequestReviewEffort
                ?? (inheritsDefaults ? settings.effort : AppSettings.defaultEffortLevel)
        )
    }

    func reviewTeamLeadProviderOptions(_ settings: AppSettings) -> [String] {
        [Self.pullRequestReviewInheritValue]
            + pullRequestReviewPeerProviderOptions(including: reviewTeamDraftLead(settings).providerID)
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

    func reviewTeamLeadProviderLabel(_ value: String, settings: AppSettings) -> String {
        value == Self.pullRequestReviewInheritValue
            ? "Default (\(providerDisplayName(for: settings.defaultProvider)))"
            : providerDisplayName(for: value)
    }

    func reviewTeamLeadModelLabel(_ value: String, settings: AppSettings) -> String {
        var inherited = settings
        inherited.pullRequestReviewModel = nil
        let lead = reviewTeamDraftLead(value == Self.pullRequestReviewInheritValue ? inherited : settings)
        let label = pullRequestReviewPeerModelLabel(
            value == Self.pullRequestReviewInheritValue ? lead.model : value,
            providerID: lead.providerID
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

    func setReviewTeamLeadProvider(_ value: String, in settings: inout AppSettings) {
        settings.pullRequestReviewProvider = value == Self.pullRequestReviewInheritValue ? nil : value
        settings.pullRequestReviewModel = nil
        settings.pullRequestReviewEffort = nil
    }

    func setReviewTeamLeadModel(_ value: String, in settings: inout AppSettings) {
        if value == Self.pullRequestReviewInheritValue {
            settings.pullRequestReviewModel = nil
            settings.pullRequestReviewEffort = nil
        } else {
            let providerID = reviewTeamDraftLead(settings).providerID
            let model = pullRequestReviewPeerStoredModel(providerID: providerID, selection: value)
            settings.pullRequestReviewModel = model
            settings.pullRequestReviewEffort = pullRequestReviewPeerDefaultEffort(providerID: providerID, model: model)
        }
    }
}
