enum ComposerMode: Sendable {
    case idle
    case busy(canStop: Bool)
    case progressOnly(ProgressReason)

    enum ProgressReason: Sendable {
        case initialSetup
        case reconfiguringSession
    }
}
