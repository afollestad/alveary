import Foundation

/// One of the review footer's state changes for the pull request itself, and the
/// rules for when GitHub allows it.
struct PullRequestStateAction: Equatable, Identifiable {
    enum Kind: Hashable {
        case close
        case reopen
        case markReady
    }

    let kind: Kind
    let title: String
    let isEnabled: Bool
    /// Why the action is unavailable, shown above the footer's buttons.
    let disabledNote: String?

    var id: Kind { kind }

    /// Closing is the only action here that throws work away, so it is the only
    /// one that wears the destructive red. Reopening and leaving draft stay
    /// secondary — the stand-in shown while the detail loads follows the same
    /// rule, so the color does not change when the detail lands.
    var isDestructive: Bool {
        kind == .close
    }

    /// Every state change available on the pull request, **default selection
    /// first**. Empty means the footer shows no state button at all: the detail
    /// has not loaded, the viewer lacks write permission, or the pull request is
    /// merged (GitHub offers neither close nor reopen on a merged pull request).
    static func available(for detail: PullRequestDetail?) -> [PullRequestStateAction] {
        guard let detail, detail.viewerCanUpdate else {
            return []
        }
        return available(status: detail.status, detail: detail)
    }

    /// The disabled stand-in the footer shows while the detail is unavailable,
    /// titled from the list row's already-known status. Without it the footer
    /// would paint a lone trailing button and then snap to the even split once
    /// the detail lands. Nil for a merged pull request, which never gets a state
    /// button; write permission is unknown until the detail arrives, so a viewer
    /// without it still sees the stand-in first.
    static func placeholder(for status: PullRequestStatus) -> PullRequestStateAction? {
        // Titled like the eventual default so the label does not change under
        // the pointer when the detail resolves.
        guard let action = available(status: status, detail: nil).first else {
            return nil
        }
        return PullRequestStateAction(
            kind: action.kind,
            title: action.title,
            isEnabled: false,
            disabledNote: nil
        )
    }

    /// Shared by the live policy and the placeholder. A nil `detail` means the
    /// status is all that is known: node id and head-branch checks fall back to
    /// what the loaded pull request would most likely offer.
    private static func available(
        status: PullRequestStatus,
        detail: PullRequestDetail?
    ) -> [PullRequestStateAction] {
        switch status {
        case .merged:
            return []
        case .closed:
            return [reopen(detail)]
        case .open:
            return [close]
        case .draft:
            // Leaving draft is the likelier action on a draft, so it leads; the
            // mutation is addressed by node id, so a loaded detail needs one.
            guard detail == nil || detail?.nodeID != nil else {
                return [close]
            }
            return [markReady, close]
        }
    }

    private static let close = PullRequestStateAction(
        kind: .close,
        title: "Close PR",
        isEnabled: true,
        disabledNote: nil
    )

    private static let markReady = PullRequestStateAction(
        kind: .markReady,
        title: "Mark ready for review",
        isEnabled: true,
        disabledNote: nil
    )

    /// A nil detail is the placeholder path, where the head branch is unknown;
    /// it renders disabled regardless, so assume the branch is still there.
    private static func reopen(_ detail: PullRequestDetail?) -> PullRequestStateAction {
        let headRefExists = detail?.headRefExists ?? true
        return PullRequestStateAction(
            kind: .reopen,
            title: "Reopen PR",
            isEnabled: headRefExists,
            disabledNote: headRefExists ? nil : deletedBranchNote(detail?.headRefName ?? "")
        )
    }

    /// Reopening without the head branch fails with HTTP 422, so the footer says
    /// why the button is dead rather than letting the request fail.
    private static func deletedBranchNote(_ branch: String) -> String {
        guard !branch.isEmpty else {
            return "The head branch has been deleted."
        }
        return "The \(branch) branch has been deleted."
    }
}
