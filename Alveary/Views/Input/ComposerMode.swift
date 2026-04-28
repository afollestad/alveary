enum ComposerMode: Sendable {
    case idle
    case busy(canStop: Bool)
    case progressOnly(ProgressReason)

    enum ProgressReason: Sendable {
        case initialSetup
        case cancellingInitialSetup
        case reconfiguringSession
        case sessionHandoff
        case toolApproval(DeferredToolComposerStatusText)

        var canStop: Bool {
            switch self {
            case .initialSetup: return true
            case .cancellingInitialSetup, .reconfiguringSession, .sessionHandoff, .toolApproval: return false
            }
        }
    }
}
