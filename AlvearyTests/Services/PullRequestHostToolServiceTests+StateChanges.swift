import AgentCLIKit
import Foundation
import XCTest

@testable import Alveary

extension PullRequestHostToolServiceTests {
    func testClosingAnOpenPullRequestAppliesImmediately() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.closeToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("closed"))
        XCTAssertEqual(fixture.pullRequests.stateChanges, [true])
        // The undo has to be named, or the model describes closing as final.
        XCTAssertTrue(result.text.contains("reopen_pr"), result.text)
    }

    func testClosingRefusesAnAutomatedScheduledRunBeforeReachingGitHub() async throws {
        let fixture = try PullRequestHostToolFixture()
        try fixture.attachAutomatedScheduledRun()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.closeToolName)

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError.automatedRunCannotClosePullRequest.localizedDescription
        )
        // The refusal is about the caller, so no detail was fetched and nothing changed.
        XCTAssertEqual(fixture.pullRequests.detailCallCount, 0)
        XCTAssertTrue(fixture.pullRequests.stateChanges.isEmpty)
    }

    func testAnAutomatedScheduledRunMayReopenAPullRequest() async throws {
        let fixture = try PullRequestHostToolFixture()
        try fixture.attachAutomatedScheduledRun()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .closed, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.reopenToolName)

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("reopened"))
        XCTAssertEqual(fixture.pullRequests.stateChanges, [false])
    }

    func testClosingAnAlreadyClosedPullRequestIsASuccessThatChangesNothing() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .closed, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.closeToolName)

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_closed"))
        XCTAssertTrue(fixture.pullRequests.stateChanges.isEmpty)
    }

    func testReopeningRefusesOnceTheHeadBranchIsGone() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .closed, viewerCanUpdate: true, headRefExists: false)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.reopenToolName)

        XCTAssertTrue(result.isError)
        // The refusal names the branch, mirroring the pane's disabled Reopen note; letting the
        // call through would surface GitHub's bare 422 instead.
        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError
                .cannotReopenWithoutHeadBranch(branch: "feat/change")
                .localizedDescription
        )
        XCTAssertTrue(fixture.pullRequests.stateChanges.isEmpty)
    }

    func testReopeningAClosedPullRequestAppliesImmediately() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .closed, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.reopenToolName)

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("reopened"))
        XCTAssertEqual(fixture.pullRequests.stateChanges, [false])
    }

    func testMarkingADraftReadyUsesItsNodeID() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .draft, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.markReadyToolName)

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("marked_ready"))
        XCTAssertEqual(fixture.pullRequests.readyForReviewNodeIDs, ["PR_7"])
    }

    func testMarkingAClosedPullRequestReadyIsRefused() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .closed, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.markReadyToolName)

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError
                .cannotMarkClosedPullRequestReady(status: "closed")
                .localizedDescription
        )
        XCTAssertTrue(fixture.pullRequests.readyForReviewNodeIDs.isEmpty)
    }

    func testMarkingANonDraftReadyIsASuccessThatChangesNothing() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.markReadyToolName)

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_ready"))
        XCTAssertTrue(fixture.pullRequests.readyForReviewNodeIDs.isEmpty)
    }

    func testMarkingAnOpenPullRequestAsDraftUsesItsNodeID() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.markDraftToolName)

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("marked_draft"))
        XCTAssertEqual(fixture.pullRequests.convertToDraftNodeIDs, ["PR_7"])
        // The undo has to be named, the way closing names reopen_pr.
        XCTAssertTrue(result.text.contains("mark_pr_ready"), result.text)
    }

    func testMarkingAClosedPullRequestAsDraftIsRefused() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .closed, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.markDraftToolName)

        XCTAssertTrue(result.isError)
        XCTAssertEqual(
            result.text,
            PullRequestHostToolServiceError
                .cannotConvertPullRequestToDraft(status: "closed")
                .localizedDescription
        )
        XCTAssertTrue(fixture.pullRequests.convertToDraftNodeIDs.isEmpty)
    }

    func testMarkingADraftAsDraftIsASuccessThatChangesNothing() async throws {
        let fixture = try PullRequestHostToolFixture()
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        fixture.pullRequests.detailResult = .success(
            makePullRequestDetail(id: identifier, status: .draft, viewerCanUpdate: true)
        )

        let result = await fixture.handle(PullRequestHostToolCatalog.markDraftToolName)

        XCTAssertEqual(try object(result.structuredContent)["status"], .string("already_draft"))
        XCTAssertTrue(fixture.pullRequests.convertToDraftNodeIDs.isEmpty)
    }

    /// Both draft directions are GraphQL mutations addressed by node id, so neither may reach
    /// GitHub without one — the pane drops both buttons in the same case.
    func testDraftDirectionsRefuseWithoutANodeID() async throws {
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        let cases = [
            (PullRequestHostToolCatalog.markReadyToolName, PullRequestStatus.draft),
            (PullRequestHostToolCatalog.markDraftToolName, PullRequestStatus.open)
        ]

        for (tool, status) in cases {
            let fixture = try PullRequestHostToolFixture()
            fixture.pullRequests.detailResult = .success(
                makePullRequestDetail(id: identifier, status: status, viewerCanUpdate: true, nodeID: nil)
            )

            let result = await fixture.handle(tool)

            XCTAssertTrue(result.isError, tool)
            XCTAssertEqual(
                result.text,
                PullRequestHostToolServiceError
                    .pullRequestUnavailable("Alveary could not read that pull request's GitHub node ID.")
                    .localizedDescription,
                tool
            )
            XCTAssertTrue(fixture.pullRequests.readyForReviewNodeIDs.isEmpty, tool)
            XCTAssertTrue(fixture.pullRequests.convertToDraftNodeIDs.isEmpty, tool)
        }
    }

    /// Every state change shares the permission and merged gates, so one table covers all four.
    func testStateChangesShareThePermissionAndMergedGates() async throws {
        let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
        let stateTools = [
            PullRequestHostToolCatalog.closeToolName,
            PullRequestHostToolCatalog.reopenToolName,
            PullRequestHostToolCatalog.markReadyToolName,
            PullRequestHostToolCatalog.markDraftToolName
        ]

        for tool in stateTools {
            let fixture = try PullRequestHostToolFixture()
            fixture.pullRequests.detailResult = .success(makePullRequestDetail(id: identifier))
            let noPermission = await fixture.handle(tool)
            XCTAssertEqual(
                noPermission.text,
                PullRequestHostToolServiceError.stateChangeNotPermitted.localizedDescription,
                tool
            )

            fixture.pullRequests.detailResult = .success(
                makePullRequestDetail(id: identifier, status: .merged, viewerCanUpdate: true)
            )
            let merged = await fixture.handle(tool, context: fixture.agentContext(requestID: "request-2"))
            XCTAssertEqual(
                merged.text,
                PullRequestHostToolServiceError.cannotChangeMergedPullRequest.localizedDescription,
                tool
            )
            XCTAssertTrue(fixture.pullRequests.stateChanges.isEmpty, tool)
            XCTAssertTrue(fixture.pullRequests.readyForReviewNodeIDs.isEmpty, tool)
            XCTAssertTrue(fixture.pullRequests.convertToDraftNodeIDs.isEmpty, tool)
        }
    }
}
