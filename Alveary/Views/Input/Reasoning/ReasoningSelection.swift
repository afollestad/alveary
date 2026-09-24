import AgentCLIKit
import Foundation

struct ReasoningMenuOption: Equatable {
    let value: String
    let title: String
}

struct ReasoningSelection: Equatable {
    let harnessID: String
    let harnessTitle: String
    let modelID: String
    let modelTitle: String
    let effortValue: String
    let effortTitle: String
    let effortOptions: [ReasoningMenuOption]
    let defaultEffortValue: String?
    let speedMode: AgentSpeedMode
    let supportsSpeedMode: Bool

    /// The compact selection names the active choice; the menu keeps its action-oriented default label.
    var compactModelTitle: String {
        harnessID == "opencode" && modelID == AppSettings.defaultModelValue ? "OpenCode default" : modelTitle
    }

    var accessibilityValue: String {
        let reasoningValue = effortOptions.isEmpty ? compactModelTitle : "\(compactModelTitle), \(effortTitle)"
        guard supportsSpeedMode, speedMode == .fast else {
            return reasoningValue
        }
        return "\(reasoningValue), Fast"
    }
}

extension ReasoningSelection {
    /// Resolves display titles from a harness catalog. `modelID` is the picker value, and `effortOptions` arrive already
    /// gated by the caller, since the composer hides effort until discovery confirms the harness supports it.
    init(
        harnessID: String,
        harnessTitle: String,
        modelOptions: [AgentModelOption],
        modelID: String,
        effortOptions: [AgentHarnessOption],
        effortValue: String,
        speedMode: AgentSpeedMode = .standard,
        supportsSpeedMode: Bool = false
    ) {
        let modelTitle = AgentModelOptionSelection.menuItems(
            in: modelOptions,
            selectedModel: modelID,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).first { $0.value == modelID }?.title ?? ChatComposerTextSupport.modelLabel(for: modelID)
        let menuOptions = effortOptions.map { ReasoningMenuOption(value: $0.value, title: $0.label) }
        let defaultEffort = AgentModelOptionSelection.defaultEffortValue(in: modelOptions, selectedModel: modelID)
        self.init(
            harnessID: harnessID,
            harnessTitle: harnessTitle,
            modelID: modelID,
            modelTitle: modelTitle,
            effortValue: effortValue,
            effortTitle: menuOptions.first { $0.value == effortValue }?.title ?? ChatComposerTextSupport.effortLabel(for: effortValue),
            effortOptions: menuOptions,
            defaultEffortValue: menuOptions.contains { $0.value == defaultEffort } ? defaultEffort : menuOptions.first?.value,
            speedMode: speedMode,
            supportsSpeedMode: supportsSpeedMode
        )
    }
}

struct ReasoningModelOption: Equatable {
    let harnessID: String
    let value: String
    let title: String
    /// Harness-supplied alias the `/model` command accepts as typed input.
    let shortName: String

    init(harnessID: String, value: String, title: String, shortName: String? = nil) {
        self.harnessID = harnessID
        self.value = value
        self.title = title
        self.shortName = shortName ?? value
    }

    var identity: String {
        // Model IDs such as `default` can appear under multiple harnesses.
        "\(harnessID):\(value)"
    }
}

struct ReasoningModelGroup: Equatable {
    let harnessID: String
    let harnessTitle: String?
    let options: [ReasoningModelOption]
}

extension ReasoningModelGroup {
    /// One row per catalog option, plus a repair row when `selectedModel` matches none of them.
    init(harnessID: String, harnessTitle: String?, modelOptions: [AgentModelOption], selectedModel: String?) {
        let options = AgentModelOptionSelection.menuItems(
            in: modelOptions,
            selectedModel: selectedModel,
            fallbackTitle: ChatComposerTextSupport.modelLabel(for:)
        ).map { item in
            ReasoningModelOption(harnessID: harnessID, value: item.value, title: item.title, shortName: item.shortName)
        }
        self.init(harnessID: harnessID, harnessTitle: harnessTitle, options: options)
    }
}
