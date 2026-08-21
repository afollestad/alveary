import Foundation

/// Which conversations are publishing a review proposal to GitHub right now, so archiving or
/// deleting one of their threads is refused for as long as that takes.
///
/// App-scoped, and fed by notification rather than by injection, because the writer and the readers
/// sit on opposite sides of a window boundary: `PullRequestReviewProposalCoordinator` knows the span
/// but is built per window (`ContentView+Factories`), while `ThreadLifecycleService` is app-scoped
/// and serves the `archive_thread` host tool with no window at all. Injecting this into the
/// coordinator would thread it through that window's bootstrap for one reader that never sees a
/// window; observing instead keeps the dependency one-way, as `PullRequestAgenticThreadActivity`
/// does with `.agentStatusChanged`.
///
/// Membership spans exactly `confirm`'s network work, opened and closed by `beginSubmitting` and
/// `endSubmitting`, so a submit that throws releases the thread as surely as one that lands. Both
/// posts are synchronous on the main actor, so the count is current before `confirm`'s first
/// suspension — which is what lets a guard read it and be right.
///
/// A pending card holds nothing here. Only work already underway blocks a thread's lifecycle, the
/// rule `activeScheduledTaskRunError` states for scheduled runs.
///
/// The sidebar's working ring spans the same submits but deliberately does not read this: a
/// notification-fed plain class publishes nothing SwiftUI observes, so a row reading it would never
/// repaint. `ConversationWorkActivity` takes the per-window coordinator's `@Observable` half
/// instead, which is also the seam to union this in should a second window ever need the ring.
@MainActor
final class PullRequestReviewSubmissionActivity {
    /// The app-wide instance every lifecycle guard reads. A shared static rather than a DI edge
    /// because this type derives its whole state from a broadcast — two instances observing the
    /// same centre agree — and threading it through `ContentViewDependencies` would grow that
    /// struct for a reader that never sees a window. `ProjectConfigStore.shared` is the precedent,
    /// and tests drive this one through the real notification rather than injecting a stand-in —
    /// the broadcast *is* the wiring, so posting is what proves it.
    ///
    /// It must exist before the *first* post, not merely before the first read: a dropped `begin`
    /// leaves the count at zero and lets an archive through mid-submit. Every reader is a
    /// `ThreadLifecycleService`, and one is built at window bootstrap — before any transcript exists
    /// to confirm a card from — so that init's default argument is what registers the observer in
    /// time.
    static let shared = PullRequestReviewSubmissionActivity()

    private let notificationCenter: NotificationCenter
    /// Counted rather than a `Set`: two windows can hold coordinators that each announce for the
    /// same conversation, and a plain remove on the first `defer` would unblock a thread whose
    /// other submit is still in flight.
    private var submissionCounts: [String: Int] = [:]
    private var observer: (any NSObjectProtocol)?

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
        observeSubmissions()
    }

    deinit {
        MainActor.assumeIsolated {
            if let observer {
                notificationCenter.removeObserver(observer)
            }
        }
    }

    /// Announces one end of a submission span. Declared here rather than on the coordinator so the
    /// name, the keys, and the two values that travel under them stay in one place.
    ///
    /// Posts synchronously, so a caller that announces before its first `await` can rely on every
    /// guard seeing the span already open.
    static func post(conversationID: String, isSubmitting: Bool, on center: NotificationCenter) {
        center.post(
            name: .pullRequestReviewSubmissionChanged,
            object: nil,
            userInfo: [
                PullRequestReviewSubmissionKey.conversationID: conversationID,
                PullRequestReviewSubmissionKey.isSubmitting: isSubmitting
            ]
        )
    }

    /// Whether nothing at all is publishing, so a per-row caller can skip resolving conversation
    /// ids for the overwhelmingly common case. The sidebar reads the guard once per visible row per
    /// render, and `thread.conversations` is a SwiftData relationship traversal plus an allocation.
    var isIdle: Bool {
        submissionCounts.isEmpty
    }

    private func isSubmitting(conversationID: String) -> Bool {
        submissionCounts[conversationID, default: 0] > 0
    }

    /// The only read, and the shape a thread's guard needs: a thread owns several conversations,
    /// and any one of them mid-submit blocks it.
    func isSubmitting(anyOf conversationIDs: some Sequence<String>) -> Bool {
        conversationIDs.contains { isSubmitting(conversationID: $0) }
    }

    /// Observed synchronously (`queue: nil`) so the span is closed on the poster's own turn. Every
    /// poster is `@MainActor`, which is what `assumeIsolated` rests on.
    private func observeSubmissions() {
        observer = notificationCenter.addObserver(
            forName: .pullRequestReviewSubmissionChanged,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            // Unpacked out here, not inside the hop: `Notification` is not `Sendable`, the two
            // values are.
            guard let conversationID = notification.userInfo?[
                PullRequestReviewSubmissionKey.conversationID
            ] as? String,
                let isSubmitting = notification.userInfo?[
                    PullRequestReviewSubmissionKey.isSubmitting
                ] as? Bool else {
                return
            }
            MainActor.assumeIsolated {
                self?.apply(conversationID: conversationID, isSubmitting: isSubmitting)
            }
        }
    }

    private func apply(conversationID: String, isSubmitting: Bool) {
        let count = submissionCounts[conversationID, default: 0]
        guard isSubmitting else {
            // Clamped at zero so an unpaired end — a coordinator built after a submit began —
            // cannot drive the count negative and wedge the conversation as permanently blocked.
            submissionCounts[conversationID] = count > 1 ? count - 1 : nil
            return
        }
        submissionCounts[conversationID] = count + 1
    }
}

extension Notification.Name {
    /// Posted when a conversation starts or finishes publishing its review proposal. Declared beside
    /// the tracker that consumes it, as `.pullRequestAgenticThreadActivityChanged` is declared
    /// beside the one that posts it.
    static let pullRequestReviewSubmissionChanged = Notification.Name(
        "pullRequestReviewSubmissionChanged"
    )
}

enum PullRequestReviewSubmissionKey {
    static let conversationID = "conversationID"
    static let isSubmitting = "isSubmitting"
}
