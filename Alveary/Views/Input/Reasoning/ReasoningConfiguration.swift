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

    /// Model selection is the only useful content when neither effort nor speed controls are available.
    var showsOnlyModels: Bool {
        selection.effortOptions.isEmpty && !selection.supportsSpeedMode
    }
}
