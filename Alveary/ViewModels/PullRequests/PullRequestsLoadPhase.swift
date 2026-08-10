import Foundation

/// Why the pull requests screen has no list to show, as opposed to an empty one.
enum PullRequestsUnavailableReason: Equatable {
    case notInstalled
    case notAuthenticated
    case rateLimited
    case failed(String)

    /// A refresh failure only replaces the list when the cause is the integration itself; anything
    /// else keeps the stale rows and surfaces a banner instead.
    init(_ error: PullRequestsServiceError) {
        switch error {
        case .ghNotInstalled:
            self = .notInstalled
        case .notAuthenticated:
            self = .notAuthenticated
        case .rateLimited:
            self = .rateLimited
        case .requestFailed, .responseTooLarge, .decodingFailed, .transport:
            self = .failed(error.localizedDescription)
        }
    }
}

enum PullRequestsLoadPhase: Equatable {
    case idle
    case loading
    case loaded
    case unavailable(PullRequestsUnavailableReason)
}
