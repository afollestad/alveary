import Foundation

/// The review footer's trailing split button: write the review yourself, or hand either half of
/// the pull request's life to an agent. Unlike `PullRequestStateAction` there is no availability
/// policy — every option applies to every pull request, and `propose_pr_review` validates the
/// verdict when the agent proposes one. Which one *leads* is `PullRequestReviewFooterAuthorship`'s
/// to say.
struct PullRequestReviewFooterAction: Equatable, Identifiable {
    enum Kind: String, CaseIterable {
        case submitReview
        case agenticReview
        case addressFeedback
    }

    let kind: Kind
    let title: String

    var id: Kind { kind }

    /// The brain glyph matches the Agents settings page, the app's one symbol for
    /// "an agent does this" — so both agentic options wear it.
    var icon: ActionIcon {
        switch kind {
        case .submitReview:
            return .octicon(.codeReview16)
        case .agenticReview, .addressFeedback:
            return .system("brain")
        }
    }

    /// Menu order, reading left to right through the pull request's life: review it, then answer
    /// what came back. The leading action is the authorship's stored pick, not this list's head.
    static let all: [PullRequestReviewFooterAction] = [
        PullRequestReviewFooterAction(kind: .submitReview, title: "Submit review..."),
        PullRequestReviewFooterAction(kind: .agenticReview, title: "Agentic review"),
        PullRequestReviewFooterAction(kind: .addressFeedback, title: "Address feedback")
    ]

    static func action(for kind: Kind) -> PullRequestReviewFooterAction {
        all.first { $0.kind == kind } ?? all[0]
    }

    /// Which option the split button's face shows.
    ///
    /// A written review outranks the stored pick until the user picks otherwise: with comments
    /// staged, finishing that review is the likely intent, so it leads — but `hasPicked` wins,
    /// because an agentic review reads what is staged through `get_pr_review_proposal` and carries
    /// it forward rather than discarding it.
    ///
    /// Overriding a pick unconditionally is what made the button look broken: the caret stored a
    /// choice and the very next render replaced it, so neither agentic option could be selected or
    /// run while a proposal was pending. Lives here rather than in the footer so the rule is
    /// testable without driving a SwiftUI `@State`.
    static func leadingKind(
        selected: Kind,
        hasPicked: Bool,
        hasStagedComments: Bool
    ) -> Kind {
        guard !hasPicked, hasStagedComments else {
            return selected
        }
        return .submitReview
    }

    /// A stored kind from a newer build, or none at all, falls back to the caller's default
    /// rather than leaving the footer without a button. The default is a parameter because it
    /// depends on who wrote the pull request.
    static func kind(fromStored raw: String?, default fallback: Kind) -> Kind {
        raw.flatMap(Kind.init(rawValue:)) ?? fallback
    }
}
