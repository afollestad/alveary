import Foundation
import XCTest

@testable import Alveary

/// Inline pull request description editing: permission gating plus the same
/// optimistic-apply-and-revert shape the comment and review edits use.
@MainActor
extension PullRequestsViewModelTests {
    private func detail(id: PullRequestIdentifier, canUpdate: Bool) -> PullRequestDetail {
        var detail = makePullRequestDetail(id: id)
        detail.viewerCanUpdate = canUpdate
        return detail
    }

    private func openedPane(
        canUpdate: Bool,
        updateResult: Result<Void, PullRequestsServiceError> = .success(())
    ) async -> (viewModel: PullRequestsViewModel, service: StubPullRequestsService) {
        let service = StubPullRequestsService()
        let summary = makePullRequestSummary(number: 7)
        service.detailResult = .success(detail(id: summary.id, canUpdate: canUpdate))
        service.diffResult = .success(makeUnifiedDiffFixture(fileCount: 1))
        service.updatePullRequestBodyResult = updateResult
        let viewModel = makePullRequestsViewModel(service: service)
        viewModel.requestDetails(summary)
        await waitForPaneContent(viewModel, target: .details(summary.id))
        return (viewModel, service)
    }

    func testDescriptionEditAppliesOptimisticallyWithoutRefetch() async {
        let (viewModel, service) = await openedPane(canUpdate: true)
        let detailCallsBefore = service.detailCallCount

        viewModel.openDescriptionEditor()
        XCTAssertEqual(viewModel.activePaneSession?.isEditingDescription, true)
        // The editor seeds from the current body, and no comment target is set.
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Body")
        XCTAssertNil(viewModel.activePaneSession?.composerAnchor)
        XCTAssertNil(viewModel.activePaneSession?.composerIssueCommentID)
        XCTAssertNil(viewModel.activePaneSession?.composerReviewID)

        viewModel.updateComposerText("Rewritten description")
        viewModel.saveComposerComment()

        XCTAssertEqual(viewModel.activePaneSession?.detail?.bodyMarkdown, "Rewritten description")
        XCTAssertEqual(viewModel.activePaneSession?.isEditingDescription, false)

        for _ in 0..<2_000 where service.updatedDescriptions.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(service.updatedDescriptions, ["Rewritten description"])
        // Description edits never touch comment endpoints and never refetch.
        XCTAssertEqual(service.updatedIssueComments, [])
        XCTAssertEqual(service.updatedReviews, [])
        XCTAssertEqual(service.detailCallCount, detailCallsBefore)
    }

    func testDescriptionEditFailureRevertsBodyAndReopensEditor() async {
        let (viewModel, service) = await openedPane(
            canUpdate: true,
            updateResult: .failure(.requestFailed(statusCode: 403))
        )

        viewModel.openDescriptionEditor()
        viewModel.updateComposerText("Rewritten description")
        viewModel.saveComposerComment()

        for _ in 0..<2_000 where viewModel.activePaneSession?.composerError == nil {
            await Task.yield()
        }

        // The original body is restored and the editor reopens with the attempt.
        XCTAssertEqual(viewModel.activePaneSession?.detail?.bodyMarkdown, "Body")
        XCTAssertEqual(viewModel.activePaneSession?.isEditingDescription, true)
        XCTAssertEqual(viewModel.activePaneSession?.composerText, "Rewritten description")
        XCTAssertNotNil(viewModel.activePaneSession?.composerError)
        XCTAssertEqual(service.updatedDescriptions, ["Rewritten description"])
    }

    /// GitHub gates body edits on `viewerCanUpdate`, not authorship.
    func testDescriptionEditorRejectsMissingPermission() async {
        let (viewModel, service) = await openedPane(canUpdate: false)

        viewModel.openDescriptionEditor()

        XCTAssertEqual(viewModel.activePaneSession?.isEditingDescription, false)
        XCTAssertNil(viewModel.composerDraft)
        XCTAssertEqual(service.updatedDescriptions, [])
    }

    /// A description may legitimately be cleared, unlike a comment, which would
    /// be a no-op save.
    func testClearingTheDescriptionSaves() async {
        let (viewModel, service) = await openedPane(canUpdate: true)

        viewModel.openDescriptionEditor()
        viewModel.updateComposerText("")
        viewModel.saveComposerComment()

        for _ in 0..<2_000 where service.updatedDescriptions.isEmpty {
            await Task.yield()
        }
        XCTAssertEqual(service.updatedDescriptions, [""])
        XCTAssertEqual(viewModel.activePaneSession?.detail?.bodyMarkdown, "")
    }

    func testCancellingTheDescriptionEditorLeavesTheBodyIntact() async {
        let (viewModel, service) = await openedPane(canUpdate: true)

        viewModel.openDescriptionEditor()
        viewModel.updateComposerText("Discarded")
        viewModel.cancelCommentComposer()

        XCTAssertEqual(viewModel.activePaneSession?.isEditingDescription, false)
        XCTAssertEqual(viewModel.activePaneSession?.detail?.bodyMarkdown, "Body")
        XCTAssertNil(viewModel.composerDraft)
        XCTAssertEqual(service.updatedDescriptions, [])
    }
}
