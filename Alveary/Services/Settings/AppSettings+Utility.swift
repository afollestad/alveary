import Foundation

/// Utility pins follow Threads only while their harness matches, so a provider's model never leaks into another provider.
extension AppSettings {
    var effectiveUtilityHarness: String { utilityHarness ?? defaultHarness }
    var effectiveUtilityModel: String {
        utilityModel ?? (effectiveUtilityHarness == defaultHarness ? defaultModel : Self.defaultModelValue)
    }
    var effectiveUtilityEffort: String {
        utilityEffort ?? (effectiveUtilityHarness == defaultHarness ? effort : effectiveUtilityHarness == "opencode"
            ? Self.openCodeDefaultEffort : Self.defaultEffortLevel)
    }
}
