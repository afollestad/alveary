import Foundation

enum ExitPlanModeDenialPolicy {
    static let deniedResponseText = "The host chose to stay in plan mode."

    static func requiresRevisionTransportGuidance(providerId: String?) -> Bool {
        providerId == "claude"
    }

    static func revisionTransportText(visibleText: String) -> String {
        // Alveary's plan-mode state is host-side and is not reliably model-visible to Claude
        // after denied `ExitPlanMode`, so Claude needs explicit provider-facing guidance.
        let guidance = "The user rejected the plan and Alveary is still in plan mode. " +
            "Treat the following as plan-revision feedback only. " +
            "Do not make file or tool changes yet. " +
            "Revise the plan, then request ExitPlanMode again when ready."

        return """
        \(guidance)

        User feedback:
        \(visibleText)
        """
    }
}
