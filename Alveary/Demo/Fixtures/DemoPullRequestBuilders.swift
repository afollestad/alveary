#if DEBUG
import Foundation

// Short constructors for the pull-request conversation models, so a fixture names only the fields
// it varies. They hang off the models rather than off `DemoPullRequestFixtures` so an array
// literal can call them through implicit member lookup: `[.demo("priya", …), .demo("marcus", …)]`.
//
// Avatar URLs stay nil throughout: every surface then renders its deterministic letter placeholder
// instead of fetching, which demo mode has no business doing.

extension PullRequestComment {
    /// A submitted comment. Edit and delete follow GitHub permissions rather than authorship, but
    /// the fixtures have only one viewer, so attributing it to them is what grants the `⋯` menu.
    static func demo(
        _ author: String,
        _ body: String,
        at date: Date,
        id: Int,
        isBot: Bool = false
    ) -> PullRequestComment {
        PullRequestComment(
            authorLogin: author,
            authorAvatarURL: nil,
            bodyMarkdown: body,
            createdAt: date,
            databaseId: id,
            nodeID: "demo-comment-\(id)",
            viewerCanUpdate: author == DemoPullRequestFixtures.viewerLogin,
            viewerCanDelete: author == DemoPullRequestFixtures.viewerLogin,
            isBot: isBot
        )
    }

    /// The viewer's own unsubmitted review comment — the orange "Pending" pill. It carries no
    /// `databaseId` because nothing about it exists on GitHub's REST side until the review is sent.
    static func demoPending(_ body: String, at date: Date, id: Int) -> PullRequestComment {
        PullRequestComment(
            authorLogin: DemoPullRequestFixtures.viewerLogin,
            authorAvatarURL: nil,
            bodyMarkdown: body,
            createdAt: date,
            nodeID: "demo-comment-\(id)",
            isPending: true
        )
    }

    /// Reactions ride along as a separate step so `demo(_:_:at:id:)` keeps a short signature;
    /// `reactions` is one of the few `var`s on the model, which is what makes this possible.
    func reacting(_ reactions: [PullRequestCommentReaction]) -> PullRequestComment {
        var copy = self
        copy.reactions = reactions
        return copy
    }
}

extension PullRequestReview {
    /// The node id a review's threads point back at. `PullRequestActivityEntry` nests a thread
    /// under a review by matching this exactly, so both sides must derive it the same way.
    static func demoNodeID(_ id: Int) -> String {
        "demo-review-\(id)"
    }

    /// A submitted review. An empty `body` is deliberate for a carrier review: it renders as the
    /// header its threads nest under, and is hidden outright if it carries none.
    static func demo(
        _ author: String,
        _ state: PullRequestReviewState,
        body: String = "",
        at date: Date,
        id: Int
    ) -> PullRequestReview {
        PullRequestReview(
            authorLogin: author,
            authorAvatarURL: nil,
            state: state,
            bodyMarkdown: body,
            submittedAt: date,
            databaseId: id,
            nodeID: demoNodeID(id),
            viewerCanUpdate: author == DemoPullRequestFixtures.viewerLogin
        )
    }

    func reacting(_ reactions: [PullRequestCommentReaction]) -> PullRequestReview {
        var copy = self
        copy.reactions = reactions
        return copy
    }
}

extension PullRequestReviewThread {
    /// `reviewID` nil leaves the thread standalone in the Overview timeline, dated by its root
    /// comment; a value nests it under that review's card.
    static func demo(
        _ path: String,
        line: Int,
        id: Int,
        excerpt: String,
        comments: [PullRequestComment],
        reviewID: Int? = nil,
        isResolved: Bool = false,
        isOutdated: Bool = false
    ) -> PullRequestReviewThread {
        PullRequestReviewThread(
            path: path,
            line: line,
            side: .right,
            isResolved: isResolved,
            isOutdated: isOutdated,
            comments: comments,
            diffHunkExcerpt: excerpt,
            nodeID: "demo-thread-\(id)",
            reviewNodeID: reviewID.map(PullRequestReview.demoNodeID)
        )
    }
}

extension PullRequestTimelineEvent {
    static func demo(
        _ kind: Kind,
        by login: String,
        at date: Date,
        detail: String? = nil
    ) -> PullRequestTimelineEvent {
        PullRequestTimelineEvent(kind: kind, actorLogin: login, actorAvatarURL: nil, createdAt: date, detail: detail)
    }
}

extension PullRequestReviewer {
    static func demo(
        _ login: String,
        _ state: State,
        isBot: Bool = false,
        canReRequest: Bool = false
    ) -> PullRequestReviewer {
        PullRequestReviewer(login: login, avatarURL: nil, isBot: isBot, state: state, canReRequest: canReRequest)
    }
}

extension PullRequestCheck {
    static func demo(_ name: String, _ state: PullRequestChecksState, url: String? = nil) -> PullRequestCheck {
        PullRequestCheck(name: name, state: state, detailsURL: url.flatMap(URL.init(string:)))
    }
}

extension PullRequestCommentReaction {
    static func demo(
        _ content: PullRequestReactionContent,
        _ count: Int,
        viewerHasReacted: Bool = false
    ) -> PullRequestCommentReaction {
        PullRequestCommentReaction(content: content, count: count, viewerHasReacted: viewerHasReacted)
    }
}
#endif
