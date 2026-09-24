import Foundation

extension ReasoningConfiguration {
    /// `apply` stores a pick's pins and reports whether the host accepted them. Settings hosts persist no speed mode,
    /// so Fast stays hidden and rejected.
    init(presentation: AgentReasoningPresentation, apply: @escaping (AgentReasoningPins) -> Bool) {
        let outcome: (AgentReasoningPins) -> ReasoningModelSelectionOutcome = { pins in
            guard pins != presentation.pins else {
                return .unchanged(presentation.selection)
            }
            return apply(pins) ? .applied(selection: presentation.applying(pins).selection) : .rejected
        }
        self.init(
            selection: presentation.selection,
            modelGroups: presentation.modelGroups,
            onEffortChange: { effort in
                let pins = presentation.pins(forEffort: effort)
                return pins == presentation.pins || apply(pins)
            },
            onSpeedChange: { _ in false },
            onModelChange: { request in
                presentation.pins(for: request).map(outcome) ?? .rejected
            },
            inheritChoice: presentation.inheritOption.map { option in
                ReasoningInheritChoice(option: option, onSelect: {
                    option.isEnabled ? outcome(.inherited) : .rejected
                })
            }
        )
    }
}
