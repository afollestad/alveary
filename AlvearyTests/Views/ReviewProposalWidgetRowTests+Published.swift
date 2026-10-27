import AppKit
import XCTest

@testable import Alveary

/// An edit travels factory → row → card → published body → diff → comment card, and a fork that
/// drops it fails silently on the default no-op actions, so these drive the real factory tree.
@MainActor
extension ReviewProposalWidgetRowTests {
    func testEditingAPublishedCommentReachesTheCoordinatorWithItsIdentity() async throws {
        let edits = PublishedEditRecorder()
        let host = host(for: Self.publishedEntry(), configuration: Self.publishedConfiguration(edits: edits))
        let menu = try XCTUnwrap(Self.descendant(AppKitReviewProposalCommentMenuButton.self, in: host))
        XCTAssertEqual(
            menu.makeMenu().items.map(\.title), [PullRequestCommentActionsMenu.editTitle, PullRequestCommentActionsMenu.deleteTitle]
        )

        let editor = try Self.beginEditing(through: menu, in: host)
        editor.editor.draft.replaceText("Tighter.")
        editor.onSave?()
        await waitFor { edits.calls.count == 1 }

        XCTAssertEqual(edits.calls.first, ["review-1", "PRRC_1", "Tighter."])
        // Saved: the editor closes on the new text without waiting for the coordinator's re-render.
        await waitFor { Self.descendant(AppKitReviewProposalCommentEditorView.self, in: host) == nil }
        XCTAssertTrue(ReviewSummaryTestFixture.text(in: host).contains("Tighter."))
    }

    func testAFailedEditKeepsTheEditorAndItsText() async throws {
        let edits = PublishedEditRecorder(result: false)
        let host = host(for: Self.publishedEntry(), configuration: Self.publishedConfiguration(edits: edits))
        let menu = try XCTUnwrap(Self.descendant(AppKitReviewProposalCommentMenuButton.self, in: host))

        let editor = try Self.beginEditing(through: menu, in: host)
        editor.editor.draft.replaceText("Tighter.")
        editor.onSave?()
        // Busy while GitHub answers, then the failure hands the editor back.
        await waitFor {
            (ReviewSummaryTestFixture.descendant(in: editor) {
                ($0 as? NSButton)?.title == DiffCommentComposerMode.editRemote.saveTitle
            } as? NSButton)?.isEnabled == true && edits.calls.count == 1
        }

        XCTAssertTrue(Self.descendant(AppKitReviewProposalCommentEditorView.self, in: host) === editor)
        XCTAssertEqual(editor.markdown, "Tighter.")
    }

    /// Another conversation's card is read-only, as the pending card is in a fork.
    func testAPublishedCommentInAnotherConversationOffersNoActions() throws {
        let host = host(
            for: Self.publishedEntry(),
            configuration: Self.publishedConfiguration(edits: PublishedEditRecorder(), allowsActions: false)
        )

        let menu = try XCTUnwrap(Self.descendant(AppKitReviewProposalCommentMenuButton.self, in: host))
        XCTAssertTrue(menu.isHidden)
        XCTAssertTrue(ReviewSummaryTestFixture.text(in: host).contains("Consider a guard here."))
    }

    /// Cards are pooled, so a deletion above an open editor must not hand that editor to another comment.
    func testAnOpenEditorStaysOnItsCommentWhenOneAboveItIsDeleted() throws {
        var review = Self.publishedReview(comments: [.fixture(line: 1, body: "First."), .fixture(nodeID: "PRRC_2", line: 3, body: "Second.")])
        let view = AppKitReviewProposalPublishedView()
        func configure() {
            view.configure(.init(proposalID: "review-1", published: .init(review: review, allowsActions: true), typography: .init()))
        }
        configure()
        let card = try XCTUnwrap(ReviewSummaryTestFixture.descendant(in: view) {
            ($0 as? AppKitReviewProposalCommentCardView)?.publishedNodeID == "PRRC_2"
        })
        let menu = try XCTUnwrap(Self.descendant(AppKitReviewProposalCommentMenuButton.self, in: card))
        let editor = try Self.beginEditing(through: menu, in: card)
        editor.editor.draft.replaceText("Draft.")

        review.comments[0].isDeleted = true
        configure()

        XCTAssertTrue(Self.descendant(AppKitReviewProposalCommentEditorView.self, in: view) === editor)
        XCTAssertTrue(editor.isDescendant(of: card))
        XCTAssertEqual(editor.markdown, "Draft.")
    }

    func testThePublishedCaptionCountsTheCommentsItsHunksCannotPlace() {
        let review = Self.publishedReview(comments: [.fixture(), .fixture(nodeID: "PRRC_2", path: "Elsewhere.swift")])

        XCTAssertEqual(
            AppKitReviewProposalPublishedView.summary(review),
            "Published 2 review comments. 1 is not shown; open the pull request to read it."
        )
    }
}

@MainActor
private final class PublishedEditRecorder {
    let result: Bool
    var calls: [[String]] = []

    init(result: Bool = true) {
        self.result = result
    }
}

private extension ReviewProposalWidgetRowTests {
    static func publishedReview(comments: [PullRequestPublishedReview.Comment] = [.fixture()]) -> PullRequestPublishedReview {
        PullRequestPublishedReview(
            identifier: ReviewProposalFixture.identifier, sourceConversationID: "source-conversation",
            files: DiffParser.parse(makeUnifiedDiffFixture(fileCount: 1, addedLinesPerFile: 3)),
            viewerLogin: "viewer", viewerAvatarURL: nil, reviewers: [], comments: comments
        )
    }

    static func publishedEntry() -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "tool-propose-review",
            toolName: PullRequestHostToolCatalog.proposeReviewToolName,
            content: .pullRequestReviewProposal(PullRequestReviewProposalWidgetContent(
                event: .comment, identifier: ReviewProposalFixture.identifier, body: nil, commentCount: 1,
                pendingCommentCount: 0, proposalID: "review-1", message: nil, status: .pendingConfirmation
            )),
            isComplete: true,
            outcomeKey: "review-1",
            outcome: .confirmed,
            outcomeTitle: "comment",
            publishedReview: publishedReview()
        )
    }

    static func publishedConfiguration(
        edits: PublishedEditRecorder,
        allowsActions: Bool = true
    ) -> AppKitTranscriptRowFactory.Configuration {
        var configuration = AppKitTranscriptRowFactory.Configuration()
        configuration.reviewProposalState = { entry in
            entry.publishedReview.map { ReviewProposalWidgetState(published: .init(review: $0, allowsActions: allowsActions)) }
        }
        configuration.publishedReviewCommentActions.edit = { id, nodeID, body in
            edits.calls.append([id, nodeID, body])
            return edits.result
        }
        return configuration
    }

    static func beginEditing(
        through menu: AppKitReviewProposalCommentMenuButton,
        in host: NSView
    ) throws -> AppKitReviewProposalCommentEditorView {
        let item = try XCTUnwrap(menu.makeMenu().items.first { $0.title == PullRequestCommentActionsMenu.editTitle })
        _ = item.target?.perform(item.action, with: item)
        return try XCTUnwrap(descendant(AppKitReviewProposalCommentEditorView.self, in: host))
    }

    static func descendant<View: NSView>(_ type: View.Type, in view: NSView) -> View? {
        ReviewSummaryTestFixture.descendant(in: view) { $0 is View } as? View
    }
}
