import AgentCLIKit
import SwiftUI

/// Review settings also seed the team lead. Each harness picker inherits Threads defaults until explicitly pinned.
extension SettingsViewModel {
    /// Distinct from `AppSettings.defaultModelValue`, which means "the harness's default
    /// model" — a narrower claim than "follow the Threads defaults".
    static let pullRequestReviewInheritValue = "alveary.inherit"

    var pullRequestReviewPrompt: String {
        get { settingsService.current.pullRequestReviewPrompt }
        set { settingsService.update { $0.pullRequestReviewPrompt = newValue } }
    }

    var pullRequestAddressFeedbackPrompt: String {
        get { settingsService.current.pullRequestAddressFeedbackPrompt }
        set { settingsService.update { $0.pullRequestAddressFeedbackPrompt = newValue } }
    }

    var pullRequestReviewMode: PullRequestReviewMode {
        settingsService.current.pullRequestReviewMode
    }

    func setPullRequestReviewMode(_ mode: PullRequestReviewMode) {
        settingsService.update { $0.pullRequestReviewMode = mode }
    }

    var pullRequestReviewPeers: [PullRequestReviewPeer] {
        settingsService.current.pullRequestReviewPeers
    }

    func setPullRequestReviewPeers(_ peers: [PullRequestReviewPeer]) {
        settingsService.update { $0.pullRequestReviewPeers = peers }
    }

    var pullRequestReviewTeamSummary: String {
        let count = pullRequestReviewPeers.count + 1
        guard count > 1 else {
            return "Not configured"
        }
        return "\(count) reviewers · \(ReviewTeamConsensus.requiredVotes(teamSize: count)) required"
    }

    var pullRequestReviewTeamSettingsStatus: PullRequestReviewTeamSettingsStatus {
        pullRequestReviewTeamSettingsStatus(peers: pullRequestReviewPeers)
    }

    func pullRequestReviewTeamSettingsStatus(
        peers: [PullRequestReviewPeer],
        settings draftSettings: AppSettings? = nil
    ) -> PullRequestReviewTeamSettingsStatus {
        if harnessDiscovery != nil, !hasLoadedHarnessStatuses {
            return .checking
        }
        var settings = draftSettings ?? settingsService.current
        settings.pullRequestReviewPeers = peers
        do {
            _ = try PullRequestReviewTeamResolver.resolve(
                settings: settings,
                harnessStatuses: typedHarnessStatuses,
                harnessOrdering: harnessOrdering
            )
            return .ready
        } catch {
            return .needsAttention(error.localizedDescription)
        }
    }

    /// Suggests the entire first team in a local draft; unavailable exact pins stay visible for repair.
    func reviewTeamEditorSettings() -> AppSettings {
        var draft = settingsService.current
        guard draft.pullRequestReviewPeers.isEmpty else { return draft }

        draft.pullRequestReviewHarness = "codex"
        draft.pullRequestReviewModel = "gpt-5.6-sol"
        draft.pullRequestReviewEffort = "high"
        if resolvedPullRequestReviewLead(settings: draft) == nil {
            draft.pullRequestReviewHarness = "claude"
            draft.pullRequestReviewModel = "claude-opus-5"
        }
        draft.pullRequestReviewPeers = suggestedPullRequestReviewPeers()
        return draft
    }

    func pullRequestReviewPeerHarnessOptions(including harnessID: String) -> [String] {
        var values = threadDefaultHarnessIDs
        if !harnessID.isEmpty, !values.contains(harnessID) {
            values.append(harnessID)
        }
        return values
    }

    func pullRequestReviewPeerModelSelection(_ peer: PullRequestReviewPeer) -> String {
        concreteModelOption(for: peer.model, harnessID: peer.harnessID)?.id ?? peer.model
    }

    func pullRequestReviewPeerModelOptions(_ peer: PullRequestReviewPeer) -> [String] {
        var values = concreteModelOptions(for: peer.harnessID).map(\.id)
        let selection = pullRequestReviewPeerModelSelection(peer)
        if !selection.isEmpty, !values.contains(selection) {
            values.append(selection)
        }
        return values
    }

    func pullRequestReviewPeerStoredModel(harnessID: String, selection: String) -> String {
        concreteModelOptions(for: harnessID).first { $0.id == selection }?.model ?? selection
    }

    func pullRequestReviewPeerEffortOptions(_ peer: PullRequestReviewPeer) -> [String] {
        let option = concreteModelOption(for: peer.model, harnessID: peer.harnessID)
        var values = option?.supportedEffortOptions.map(\.value) ?? []
        if !peer.effort.isEmpty, !values.contains(peer.effort) {
            values.append(peer.effort)
        }
        if values.isEmpty {
            values = [AppSettings.defaultEffortLevel]
        }
        return values
    }

    func pullRequestReviewPeerModelLabel(_ value: String, harnessID: String) -> String {
        concreteModelOption(for: value, harnessID: harnessID)?.label
            ?? ChatComposerTextSupport.modelLabel(for: value)
    }

    func pullRequestReviewPeerEffortLabel(_ value: String, peer: PullRequestReviewPeer) -> String {
        let option = concreteModelOption(for: peer.model, harnessID: peer.harnessID)
        return option?.supportedEffortOptions.first { $0.value == value }?.label
            ?? ChatComposerTextSupport.effortLabel(for: value)
    }

    func defaultPullRequestReviewPeer(
        harnessID: String,
        excluding peers: [PullRequestReviewPeer],
        settings draftSettings: AppSettings? = nil
    ) -> PullRequestReviewPeer? {
        var excludedModels = Set(peers.filter { $0.harnessID == harnessID }.map(\.model))
        if let lead = resolvedPullRequestReviewLead(settings: draftSettings), harnessID == lead.harnessID {
            excludedModels.insert(lead.launchModel)
        }
        guard let option = concreteModelOptions(for: harnessID).first(where: {
            guard let model = $0.model else { return false }
            return !excludedModels.contains(model)
        }), let model = option.model else {
            return nil
        }
        return PullRequestReviewPeer(
            id: UUID().uuidString,
            harnessID: harnessID,
            model: model,
            effort: option.defaultEffortOption?.value
                ?? option.supportedEffortOptions.first?.value
                ?? AppSettings.defaultEffortLevel
        )
    }

    func nextPullRequestReviewPeer(
        excluding peers: [PullRequestReviewPeer],
        settings draftSettings: AppSettings? = nil
    ) -> PullRequestReviewPeer? {
        for harnessID in threadDefaultHarnessIDs {
            if let peer = defaultPullRequestReviewPeer(harnessID: harnessID, excluding: peers, settings: draftSettings) {
                return peer
            }
        }
        return nil
    }

    func pullRequestReviewPeerDefaultEffort(harnessID: String, model: String) -> String {
        let option = concreteModelOption(for: model, harnessID: harnessID)
        return option?.defaultEffortOption?.value
            ?? option?.supportedEffortOptions.first?.value
            ?? AppSettings.defaultEffortLevel
    }

    var pullRequestReviewEffectiveHarnessID: String { reviewAgentEditor.effectiveHarnessID }
    var pullRequestReviewHarnessSelection: String { reviewAgentEditor.harnessSelection }
    var pullRequestReviewHarnessOptions: [String] { reviewAgentEditor.harnessOptions }
    var pullRequestReviewModelSelection: String { reviewAgentEditor.modelSelection }
    var pullRequestReviewModelOptions: [String] { reviewAgentEditor.modelOptions }
    var pullRequestReviewEffortSelection: String { reviewAgentEditor.effortSelection }
    var pullRequestReviewEffortOptions: [AgentHarnessOption] { reviewAgentEditor.effortOptions }
    var pullRequestReviewPermissionSelection: String { reviewAgentEditor.permissionSelection }
    var pullRequestReviewPermissionOptions: [String] { reviewAgentEditor.permissionOptions }

    func setPullRequestReviewHarness(_ value: String) { reviewAgentEditor.setHarness(value) }
    func setPullRequestReviewModel(_ value: String) { reviewAgentEditor.setModel(value) }
    func setPullRequestReviewEffort(_ value: String) { reviewAgentEditor.setEffort(value) }
    func setPullRequestReviewPermission(_ value: String) { reviewAgentEditor.setPermission(value) }

    func pullRequestReviewLabel(forHarness value: String) -> String { reviewAgentEditor.label(forHarness: value) }
    func pullRequestReviewLabel(forModel value: String) -> String { reviewAgentEditor.label(forModel: value) }
    func pullRequestReviewLabel(forEffort value: String) -> String { reviewAgentEditor.label(forEffort: value) }
    func pullRequestReviewLabel(forPermission value: String) -> String { reviewAgentEditor.label(forPermission: value) }

    /// A review thread and a feedback thread can belong in different places. Both degrade on *read* — an id no longer
    /// among the options shows `Tasks` while the stored value survives, so re-creating the
    /// section restores the pick and no getter has to write. The `Selection` suffix the agent
    /// pickers carry is dropped here only because that spelling exceeds the identifier limit.
    var pullRequestAddressFeedbackSection: String? {
        offerableSectionID(settingsService.current.pullRequestAddressFeedbackSectionID)
    }

    func setPullRequestAddressFeedbackSection(_ value: String?) {
        settingsService.update { $0.pullRequestAddressFeedbackSectionID = value }
    }

    var pullRequestReviewSection: String? {
        offerableSectionID(settingsService.current.pullRequestReviewSectionID)
    }

    func setPullRequestReviewSection(_ value: String?) {
        settingsService.update { $0.pullRequestReviewSectionID = value }
    }

    /// Both pickers' option list: `Tasks` is the literal nil row, and only custom sections follow
    /// it — pinning and a Project placement are what put a thread in `Pinned` or `Projects`.
    var pullRequestSectionOptions: [String?] {
        [nil] + sidebarSectionOptions.map { $0.id }
    }

    func pullRequestSectionLabel(for id: String?) -> String {
        guard let id else {
            return "Tasks"
        }
        return sidebarSectionOptions.first { $0.id == id }?.name ?? "Tasks"
    }

    private func offerableSectionID(_ id: String?) -> String? {
        guard let id, sidebarSectionOptions.contains(where: { $0.id == id }) else {
            return nil
        }
        return id
    }

    private var typedHarnessStatuses: [AgentHarnessID: AgentHarnessStatus] {
        Dictionary(uniqueKeysWithValues: harnessStatuses.compactMap { key, value in
            AgentHarnessID(rawValue: key).map { ($0, value) }
        })
    }

    private func concreteModelOptions(for harnessID: String) -> [AgentModelOption] {
        guard let typedHarnessID = AgentHarnessID(rawValue: harnessID),
              let options = typedHarnessStatuses[typedHarnessID]?.modelOptions else {
            return []
        }
        return options.filter { option in
            guard let model = option.model else { return false }
            let launchModel = model.trimmingCharacters(in: .whitespacesAndNewlines)
            return !launchModel.isEmpty
                && launchModel.lowercased() != AppSettings.defaultModelValue
                && !option.supportedEffortOptions.isEmpty
        }
    }

    private func concreteModelOption(for selection: String, harnessID: String) -> AgentModelOption? {
        let options = concreteModelOptions(for: harnessID)
        if let exact = options.first(where: { $0.id == selection || $0.model == selection }) {
            return exact
        }
        return selection == AppSettings.defaultModelValue ? options.first(where: \.isDefault) : nil
    }

    private func resolvedPullRequestReviewLead(settings draftSettings: AppSettings?) -> ReviewWorkerConfiguration? {
        try? PullRequestReviewTeamResolver.resolveLead(
            settings: draftSettings ?? settingsService.current,
            harnessStatuses: typedHarnessStatuses
        )
    }

    private func suggestedPullRequestReviewPeers() -> [PullRequestReviewPeer] {
        [
            PullRequestReviewPeer(id: UUID().uuidString, harnessID: "codex", model: "gpt-6-astra", effort: "max"),
            PullRequestReviewPeer(id: UUID().uuidString, harnessID: "claude", model: "claude-fable-5-1", effort: "max")
        ].filter { peer in
            guard let status = harnessStatuses[peer.harnessID],
                  settingsService.current.isHarnessEnabled(peer.harnessID),
                  status.isEnabled, status.isInstalled, status.isSetupReady,
                  let executable = status.availability?.executablePath else { return false }
            return !executable.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

enum PullRequestReviewTeamSettingsStatus: Equatable {
    case checking
    case ready
    case needsAttention(String)
}

/// One custom sidebar section for the Git tab's pickers. Deliberately not
/// `SidebarSectionDescriptor`, whose `SidebarSectionID` would make `.pinned` and `.projects`
/// representable in a setting that must never offer them — unofferable by type, not by a filter
/// someone can forget. `ScheduledTaskSectionOption` stays its own type for the same reason;
/// neither may widen for the other.
struct SettingsSidebarSectionOption: Equatable, Identifiable {
    let id: String
    let name: String
}
