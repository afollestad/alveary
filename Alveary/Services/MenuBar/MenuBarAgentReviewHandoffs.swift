import Foundation

/// The pull requests the user has handed to an agent review, which the status menu leaves out of
/// "Needs review" and its badge until the review is submitted.
///
/// GitHub keeps the viewer's review request open until a review lands, so nothing in the search
/// changes when an agent starts one; only Alveary knows. A pull request counts as handed off while
/// either source holds it:
///
/// - `PullRequestAgenticThreadActivity` has a review route for it — from the click, through
///   preparation, while the agent works, and while a team review awaits its decision.
/// - A conversation holds a pending review proposal for it — the agent finished and the card waits
///   for the user. The envelope clears when the proposal is confirmed, rejected, or superseded, and
///   when its thread is archived or deleted.
///
/// **A release lifts the hide at once, unless GitHub changed while it was handed off.** A cancelled
/// or failed agent, a discarded proposal, or an archived or deleted thread submitted nothing, so the
/// last rows read are still right and the pull request returns immediately.
///
/// **A submitted review settles first.** `PullRequestReviewProposalCoordinator.confirm` announces
/// `.pullRequestChangedOnGitHub` before it clears the envelope, which is how a release knows a
/// review went out; nothing guarantees GitHub's search reflects it at once, so lifting the hide
/// then could flash the badge back. Such a pull request stays hidden until a read that started
/// `releaseSettle` after the release finishes, which `onChange` asks the monitor to schedule —
/// success or failure, since requiring a success would keep it hidden for as long as reads fail,
/// a whole GraphQL rate-limit window among them.
@MainActor
final class MenuBarAgentReviewHandoffs {
    /// Fired whenever what `hides(_:)` answers may have changed; `released` when a pull request is
    /// waiting on a settling read the monitor should schedule.
    var onChange: (@MainActor (_ released: Bool) -> Void)?

    /// Case-folded, so a GitHub-cased summary and a URL-parsed proposal compare equal.
    private var handedOff: Set<PullRequestIdentifier> = []
    /// Released pull requests waiting on a settling read, and when each was released.
    private var released: [PullRequestIdentifier: Date] = [:]
    /// Handed-off pull requests GitHub has changed since — a submitted review, most often.
    private var changedOnGitHub: Set<PullRequestIdentifier> = []
    /// How long after a release a read has to start before it may lift the hide.
    let releaseSettle: TimeInterval
    private var observers: [any NSObjectProtocol] = []

    private let activity: PullRequestAgenticThreadActivity?
    private let pendingProposalIdentifiers: @MainActor () -> Set<PullRequestIdentifier>
    private let notificationCenter: NotificationCenter
    private let now: @MainActor () -> Date

    /// - Parameter pendingProposalIdentifiers: the pull requests with a pending review proposal in
    ///   any conversation. A closure so the store read stays at the composition root.
    init(
        activity: PullRequestAgenticThreadActivity?,
        pendingProposalIdentifiers: @escaping @MainActor () -> Set<PullRequestIdentifier>,
        notificationCenter: NotificationCenter = .default,
        releaseSettle: TimeInterval = 10,
        now: @escaping @MainActor () -> Date = { Date() }
    ) {
        self.releaseSettle = releaseSettle
        self.activity = activity
        self.pendingProposalIdentifiers = pendingProposalIdentifiers
        self.notificationCenter = notificationCenter
        self.now = now
    }

    func hides(_ identifier: PullRequestIdentifier) -> Bool {
        let folded = Self.folded(identifier)
        return handedOff.contains(folded) || released[folded] != nil
    }

    /// Reads both sources and follows them. Synchronous observers (`queue: nil`), so a hand-off is
    /// reflected by the time the poster's `post` returns; every poster is `@MainActor`, which is
    /// what `assumeIsolated` rests on.
    func start() {
        guard observers.isEmpty else {
            return
        }
        handedOff = currentHandoffs()
        for name in [Notification.Name.pullRequestAgenticThreadActivityChanged, .pullRequestReviewProposalsChanged] {
            observers.append(notificationCenter.addObserver(forName: name, object: nil, queue: nil) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.refresh()
                }
            })
        }
        observers.append(notificationCenter.addObserver(
            forName: .pullRequestChangedOnGitHub,
            object: nil,
            queue: nil
        ) { [weak self] notification in
            guard let announcement = notification.userInfo?[PullRequestChangeNotificationKey.announcement]
                as? PullRequestChangeAnnouncement, announcement.affectsListRow else {
                return
            }
            let identifier = announcement.identifier
            MainActor.assumeIsolated {
                self?.noteChangedOnGitHub(identifier)
            }
        })
    }

    func stop() {
        for observer in observers {
            notificationCenter.removeObserver(observer)
        }
        observers = []
        handedOff = []
        released = [:]
        changedOnGitHub = []
    }

    /// Lifts the hide on everything released at least `releaseSettle` before `startedAt`, whatever
    /// the read's outcome; a cancelled read, which another replaces, should not call this.
    func readFinished(startedAt: Date) {
        released = released.filter { startedAt.timeIntervalSince($0.value) < releaseSettle }
    }

    private func refresh() {
        let current = currentHandoffs()
        let left = handedOff.subtracting(current)
        let settling = left.intersection(changedOnGitHub)
        let date = now()
        for identifier in settling {
            released[identifier] = date
        }
        changedOnGitHub.subtract(left)
        // Handed off again before the read that would have settled it.
        for identifier in current {
            released[identifier] = nil
        }
        guard current != handedOff else {
            return
        }
        handedOff = current
        onChange?(!settling.isEmpty)
    }

    private func noteChangedOnGitHub(_ identifier: PullRequestIdentifier) {
        let folded = Self.folded(identifier)
        guard handedOff.contains(folded) else {
            return
        }
        changedOnGitHub.insert(folded)
    }

    private func currentHandoffs() -> Set<PullRequestIdentifier> {
        let reviewing = activity?.reviewIdentifiers ?? []
        return reviewing.union(pendingProposalIdentifiers().map(Self.folded))
    }

    private static func folded(_ identifier: PullRequestIdentifier) -> PullRequestIdentifier {
        PullRequestAgenticThreadActivity.Key(identifier: identifier, kind: .review).identifier
    }
}
