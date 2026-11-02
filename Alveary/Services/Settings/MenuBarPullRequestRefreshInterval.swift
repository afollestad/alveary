import Foundation

/// How often the status menu re-reads the pull requests waiting on the viewer's review.
///
/// A fixed set rather than a free number: each poll is one GraphQL search, so the floor keeps a
/// misconfigured value from spending the user's shared GitHub quota, and the raw minutes are what
/// persist so a removed case decodes to the default instead of failing settings load.
enum MenuBarPullRequestRefreshInterval: Int, Codable, Sendable, CaseIterable {
    case oneMinute = 1
    case twoMinutes = 2
    case fiveMinutes = 5
    case tenMinutes = 10
    case fifteenMinutes = 15
    case thirtyMinutes = 30
    case oneHour = 60

    var duration: Duration {
        .seconds(rawValue * 60)
    }

    var label: String {
        switch self {
        case .oneMinute:
            return "1 minute"
        case .oneHour:
            return "1 hour"
        default:
            return "\(rawValue) minutes"
        }
    }
}
