import Foundation

struct ComposerCapabilities: Sendable {
    let supportedPermissionModes: [PermissionModeOption]
    let supportsMidTurnSteering: Bool
    var supportsGoalMode = false
    var supportsExistingSessionGoalStart = false
    var supportsPlanMode = false
    var supportsSpeedMode = false
    var goalModeDisabledTooltip: String?
    var planModeDisabledTooltip: String?
}
