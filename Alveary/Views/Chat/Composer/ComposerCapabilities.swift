import Foundation

struct ComposerCapabilities: Sendable {
    let supportedPermissionModes: [PermissionModeOption]
    let supportsMidTurnSteering: Bool
    var hasConfirmedHarnessDefinition = false
    var supportsGoalMode = false
    var supportsExistingSessionGoalStart = false
    var supportsPlanMode = false
    var supportsSpeedMode = false
    var supportsLocalImageInput = false
    var supportsAppShots = false
    var supportsContextCompaction = false
    var goalModeDisabledTooltip: String?
    var planModeDisabledTooltip: String?
}
