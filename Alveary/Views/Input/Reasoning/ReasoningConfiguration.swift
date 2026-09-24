import Foundation

struct ReasoningModelSelectionRequest: Equatable {
    let harnessID: String
    let modelID: String
}

enum ReasoningModelSelectionOutcome {
    case rejected
    case unchanged(ReasoningSelection)
    case applied(selection: ReasoningSelection)
}

/// Caller-owned input for the reasoning popover; each callback reports whether the host accepted the change.
struct ReasoningConfiguration {
    var selection: ReasoningSelection
    var modelGroups: [ReasoningModelGroup]
    var onEffortChange: (String) -> Bool
    var onSpeedChange: (AgentSpeedMode) -> Bool
    var onModelChange: (ReasoningModelSelectionRequest) -> ReasoningModelSelectionOutcome
    var inheritChoice: ReasoningInheritChoice?

    init(
        selection: ReasoningSelection,
        modelGroups: [ReasoningModelGroup],
        onEffortChange: @escaping (String) -> Bool,
        onSpeedChange: @escaping (AgentSpeedMode) -> Bool,
        onModelChange: @escaping (ReasoningModelSelectionRequest) -> ReasoningModelSelectionOutcome,
        inheritChoice: ReasoningInheritChoice? = nil
    ) {
        self.selection = selection
        self.modelGroups = modelGroups
        self.onEffortChange = onEffortChange
        self.onSpeedChange = onSpeedChange
        self.onModelChange = onModelChange
        self.inheritChoice = inheritChoice
    }

    /// Model selection is the only useful content when neither effort nor speed controls are available.
    var showsOnlyModels: Bool {
        selection.effortOptions.isEmpty && !selection.supportsSpeedMode
    }
}

/// The model list's leading "inherit the defaults" row, for hosts whose stored selection can defer to another setting.
struct ReasoningInheritOption: Equatable {
    let title: String
    /// Names what the inherited selection currently resolves to, e.g. `Claude · Opus 5.5 · Max`.
    let detail: String
    var isSelected: Bool
    /// `false` when the host no longer offers inheriting but the stored selection still does, so it stays visible for repair.
    let isEnabled: Bool
}

struct ReasoningInheritChoice {
    var option: ReasoningInheritOption
    let onSelect: () -> ReasoningModelSelectionOutcome
}
