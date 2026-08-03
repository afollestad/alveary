import Foundation

struct HostToolRuntimeTransition: Equatable, Sendable {
    fileprivate let stateGeneration: UInt64
    fileprivate let requiredReplacementBeforeTransition: Bool
}

extension ConversationState {
    func markHostToolsUnavailable(requiresRuntimeReplacement: Bool) {
        hostToolStateGeneration += 1
        hostToolsDisabled = true
        requiresHostToolReplacement = requiresRuntimeReplacement
        sessionContinuityNotice = "Alveary's app tools are unavailable for this task. " +
            "You can still use Alveary's own screens."
    }

    func invalidateHostToolRuntimeConfiguration() {
        hostToolStateGeneration += 1
        requiresHostToolReplacement = true
    }

    func beginHostToolRuntimeTransition() -> HostToolRuntimeTransition {
        let transition = HostToolRuntimeTransition(
            stateGeneration: hostToolStateGeneration,
            requiredReplacementBeforeTransition: requiresHostToolReplacement
        )
        requiresHostToolReplacement = false
        return transition
    }

    func finishHostToolRuntimeTransition(
        _ transition: HostToolRuntimeTransition,
        appliedRequestedConfiguration: Bool
    ) {
        guard hostToolStateGeneration == transition.stateGeneration else {
            return
        }
        requiresHostToolReplacement = appliedRequestedConfiguration
            ? false
            : transition.requiredReplacementBeforeTransition
    }
}
