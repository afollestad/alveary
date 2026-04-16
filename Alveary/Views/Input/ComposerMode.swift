enum ComposerMode: Sendable {
    case idle
    case busy(canStop: Bool)
    case progressOnly(ProgressReason)

    enum ProgressReason: Sendable {
        case initialSetup
        case cancellingInitialSetup
        case reconfiguringSession

        var canStop: Bool {
            switch self {
            case .initialSetup: return true
            case .cancellingInitialSetup, .reconfiguringSession: return false
            }
        }
    }
}
