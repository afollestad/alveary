import Foundation

/// The review footer's trailing split button: write the review yourself, or hand it
/// to an agent. Unlike `PullRequestStateAction` there is no availability policy —
/// both options apply to every pull request, and `propose_pr_review` validates the
/// verdict when the agent proposes one.
struct PullRequestReviewFooterAction: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case submitReview
        case agenticReview
    }

    let kind: Kind
    let title: String

    var id: Kind { kind }

    /// The brain glyph matches the Agents settings page, the app's one symbol for
    /// "an agent does this".
    var icon: ActionIcon {
        switch kind {
        case .submitReview:
            return .octicon("CodeReviewOcticon16")
        case .agenticReview:
            return .system("brain")
        }
    }

    /// Default selection first, so a footer with no stored pick opens the composer.
    static let all: [PullRequestReviewFooterAction] = [
        PullRequestReviewFooterAction(kind: .submitReview, title: "Submit review..."),
        PullRequestReviewFooterAction(kind: .agenticReview, title: "Agentic review")
    ]

    static func action(for kind: Kind) -> PullRequestReviewFooterAction {
        all.first { $0.kind == kind } ?? all[0]
    }

    /// A stored kind from a newer build, or none at all, falls back to the default
    /// rather than leaving the footer without a button.
    static func kind(fromStored raw: String?) -> Kind {
        raw.flatMap(Kind.init(rawValue:)) ?? .submitReview
    }
}
