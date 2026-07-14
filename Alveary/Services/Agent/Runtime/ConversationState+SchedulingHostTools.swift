import Foundation

struct SchedulingHostToolRuntimeTransition: Equatable, Sendable {
    fileprivate let stateGeneration: UInt64
    fileprivate let requiredReplacementBeforeTransition: Bool
}

extension ConversationState {
    func markSchedulingHostToolsUnavailable(requiresRuntimeReplacement: Bool) {
        schedulingHostToolStateGeneration += 1
        schedulingHostToolsDisabled = true
        requiresSchedulingHostToolReplacement = requiresRuntimeReplacement
        sessionContinuityNotice = "Natural-language scheduling is unavailable for this task. " +
            "You can still manage schedules from Scheduled."
    }

    func invalidateSchedulingHostToolRuntimeConfiguration() {
        schedulingHostToolStateGeneration += 1
        requiresSchedulingHostToolReplacement = true
    }

    func beginSchedulingHostToolRuntimeTransition() -> SchedulingHostToolRuntimeTransition {
        let transition = SchedulingHostToolRuntimeTransition(
            stateGeneration: schedulingHostToolStateGeneration,
            requiredReplacementBeforeTransition: requiresSchedulingHostToolReplacement
        )
        requiresSchedulingHostToolReplacement = false
        return transition
    }

    func finishSchedulingHostToolRuntimeTransition(
        _ transition: SchedulingHostToolRuntimeTransition,
        appliedRequestedConfiguration: Bool
    ) {
        guard schedulingHostToolStateGeneration == transition.stateGeneration else {
            return
        }
        requiresSchedulingHostToolReplacement = appliedRequestedConfiguration
            ? false
            : transition.requiredReplacementBeforeTransition
    }
}
