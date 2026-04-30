extension AppSettings {
    static let minimumSessionHandoffWindowPercentage = 70
    static let sessionHandoffWindowPercentageStep = 5
    static let defaultSessionHandoffWindowPercentage = 90
    static let supportedHandoffPercentageRange = minimumSessionHandoffWindowPercentage...100
    static let defaultSessionHandoffPrompt = SessionHandoffPromptDefaults.defaultPrompt

    static var supportedHandoffSteeringCountdownRange: ClosedRange<Int> { 5...60 }
    static var defaultHandoffSteeringCountdownSeconds: Int { 10 }
    static var supportedHandoffPromptSendCountdownRange: ClosedRange<Int> { 0...60 }
    static var defaultHandoffPromptSendCountdownSeconds: Int { 10 }

    static func normalizedSessionHandoffWindowPercentage(_ percentage: Int) -> Int {
        let clamped = min(
            max(percentage, supportedHandoffPercentageRange.lowerBound),
            supportedHandoffPercentageRange.upperBound
        )
        let step = sessionHandoffWindowPercentageStep
        return Int((Double(clamped) / Double(step)).rounded()) * step
    }

    static func normalizedHandoffSteeringCountdownSeconds(_ seconds: Int) -> Int {
        min(
            max(seconds, supportedHandoffSteeringCountdownRange.lowerBound),
            supportedHandoffSteeringCountdownRange.upperBound
        )
    }

    static func normalizedHandoffPromptSendCountdownSeconds(_ seconds: Int) -> Int {
        min(
            max(seconds, supportedHandoffPromptSendCountdownRange.lowerBound),
            supportedHandoffPromptSendCountdownRange.upperBound
        )
    }
}
