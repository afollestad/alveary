enum ComposerMode: Equatable, Sendable {
    case idle
    case busy(canStop: Bool)
    case progressOnly(ProgressReason)

    enum ProgressReason: Equatable, Sendable {
        case initialSetup
        case cancellingInitialSetup
        case reconfiguringSession
        case sessionHandoff
        case reviewTeam
        case toolApproval(DeferredToolComposerStatusText)

        var canStop: Bool {
            switch self {
            case .initialSetup, .reviewTeam: return true
            case .cancellingInitialSetup, .reconfiguringSession, .sessionHandoff, .toolApproval: return false
            }
        }
    }
}
