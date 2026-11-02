import Foundation

/// GitHub's `SubscriptionState` for the viewer on one pull request.
///
/// `unsubscribed` is not proof the viewer chose it in Alveary: involved pull requests have been
/// seen reading `unsubscribed` without ever being ignored. That is why the ignore list is local
/// and this state only reconciles it.
enum PullRequestSubscriptionState: String, Sendable, Equatable, Codable {
    /// Notified of all conversations.
    case subscribed = "SUBSCRIBED"
    /// Notified only when participating or @mentioned.
    case unsubscribed = "UNSUBSCRIBED"
    /// Never notified.
    case ignored = "IGNORED"
}

/// One pull request as `fetchSubscriptionStates(for:)` reads it.
///
/// `summary` carries the list row's fields so the ignore sync can refresh cached rows from the
/// same request; its involvement flags are unset, because a lookup by identifier has no bucket
/// to derive them from. A caller writing it into a bucket keeps that bucket's own flags.
struct PullRequestSubscriptionSnapshot: Sendable, Equatable {
    let nodeID: String
    let summary: PullRequestSummary
    let subscription: PullRequestSubscriptionState?
    let viewerCanSubscribe: Bool
}
