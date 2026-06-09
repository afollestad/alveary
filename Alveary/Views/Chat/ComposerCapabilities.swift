import Foundation

struct ComposerCapabilities: Sendable {
    let supportedPermissionModes: [PermissionModeOption]
    let supportsMidTurnSteering: Bool
    var supportsPlanMode = false
    var supportsSpeedMode = false
    var planModeDisabledTooltip: String?
}
