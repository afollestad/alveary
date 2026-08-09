import Foundation

/// Who wrote the pull request the review footer is acting on. Two footer decisions ride on it —
/// which verdicts GitHub will accept, and which of the two persisted split-button picks leads —
/// and both were resolving the same ladder separately before this named it once.
enum PullRequestReviewFooterAuthorship: Equatable {
    case authored
    case other
    /// An identifier-opened pane knows nothing about authorship until its first detail lands.
    case unknown

    /// The list row's `isAuthored` comes from the involvement search and settles first; the
    /// detail's viewer is the confirmation, and stands in when there is no row.
    static func resolve(summary: PullRequestSummary?, detail: PullRequestDetail?) -> Self {
        guard let summary else {
            return .unknown
        }
        if summary.isAuthored {
            return .authored
        }
        if let detail, let viewer = detail.viewerLogin {
            return viewer == detail.authorLogin ? .authored : .other
        }
        return .other
    }

    /// GitHub rejects Approve and Request changes on your own pull request, so they only appear
    /// for other people's. `.unknown` withholds them too — offering one GitHub would reject is
    /// worse than withholding one it would accept, and the detail is a moment away.
    var allowsVerdictEvents: Bool {
        self == .other
    }

    /// Your own pull request opens on answering its feedback; everyone else's on reviewing.
    /// `.unknown` takes the others' default, the safer read while authorship is still in flight.
    var defaultFooterActionKind: PullRequestReviewFooterAction.Kind {
        self == .authored ? .addressFeedback : .agenticReview
    }
}
