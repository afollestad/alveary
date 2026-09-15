import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension PullRequestHostToolServiceTests {
    func testStartReviewUsesSavedSettingsAndCreatesAProjectlessTaskWithoutAnnouncingGitHubChanges() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        guard case .created(let section) = try launch.sidebar.viewModel.createSection(name: "Reviews"),
              case .custom(let sectionID) = section.id else {
            return XCTFail("Failed to create review section")
        }
        launch.host.settingsService.update {
            $0.pullRequestReviewSectionID = sectionID
            $0.pullRequestReviewPermissionMode = "default"
        }
        let recorder = launch.host.recordAnnouncements()

        let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertFalse(result.isError, result.text)
        let destination = try launch.reviewThread()
        let conversation = try XCTUnwrap(destination.soleMainConversation)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("started"))
        XCTAssertEqual(content["repository"], .string("octo/alpha"))
        XCTAssertEqual(content["number"], .number(7))
        XCTAssertEqual(content["thread_id"], .string(conversation.id))
        XCTAssertEqual(content["name"], .string(destination.name))
        XCTAssertEqual(content["review_mode"], .string("singleAgent"))
        XCTAssertEqual(destination.customSection?.id, sectionID)
        XCTAssertEqual(destination.model, "sonnet")
        XCTAssertEqual(destination.effort, "high")
        XCTAssertEqual(conversation.provider, "claude")
        XCTAssertNil(destination.project)
        let workspace = try XCTUnwrap(destination.taskWorkspaceDescriptor)
        XCTAssertEqual(workspace.ownershipStrategy, .privateOwned)
        XCTAssertTrue(workspace.grantedRoots.isEmpty)
        XCTAssertNil(workspace.sourceProjectPath)
        XCTAssertEqual(launch.prompts.prompts, ["Review pull request: \(PullRequestHostToolFixture.url)"])
        XCTAssertTrue(recorder.announcements.isEmpty)
    }

    func testScheduledReviewLaunchDispatchesADedicatedTask() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        try launch.host.attachAutomatedScheduledRun()

        let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertFalse(result.isError, result.text)
        XCTAssertEqual(try object(result.structuredContent)["status"], .string("started"))
        XCTAssertEqual(launch.prompts.prompts.count, 1)
        XCTAssertNil(try launch.reviewThread().scheduledTaskRun)
    }

    func testReviewLaunchReusesAnActiveTaskAcrossRepositoryURLCaseAndRequestIdentity() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        let detail = makePullRequestDetail(
            id: try XCTUnwrap(PullRequestHostToolFixture.identifier), url: URL(string: PullRequestHostToolFixture.url)
        )
        launch.host.pullRequests.detailResult = .success(detail)

        let first = await launch.host.handle(
            PullRequestHostToolCatalog.startReviewToolName,
            arguments: ["url": .string("https://github.com/OCTO/Alpha/pull/7")]
        )
        let second = await launch.host.handle(
            PullRequestHostToolCatalog.startReviewToolName,
            context: launch.host.agentContext(requestID: "request-2")
        )

        XCTAssertFalse(first.isError, first.text)
        XCTAssertFalse(second.isError, second.text)
        XCTAssertEqual(try object(second.structuredContent)["status"], .string("existing"))
        XCTAssertEqual(try object(second.structuredContent)["thread_id"], try object(first.structuredContent)["thread_id"])
        XCTAssertEqual(launch.prompts.prompts, ["Review pull request: \(PullRequestHostToolFixture.url)"])
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 2)
    }

    func testTeamReviewLaunchReturnsWhileReviewersAreStillWorkingWithSavedCriteria() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        let gate = PullRequestsServiceGate()
        defer { gate.open() }
        await launch.worker.configure(gate: gate)
        launch.host.settingsService.update {
            $0.pullRequestReviewMode = .reviewTeam
            $0.pullRequestReviewPrompt = "Find concurrency defects."
        }

        let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertFalse(result.isError, result.text)
        let content = try object(result.structuredContent)
        let conversationID = try XCTUnwrap(try launch.reviewThread().soleMainConversation?.id)
        let run = try XCTUnwrap(launch.coordinator.runs[conversationID])
        XCTAssertEqual(content["review_mode"], .string("reviewTeam"))
        XCTAssertEqual(content["run_id"], .string(run.id))
        XCTAssertNotNil(content["phase"])
        XCTAssertTrue(run.phase.isWorking)
        XCTAssertTrue(run.criteria.contains("Find concurrency defects."))
        XCTAssertEqual(run.team.map(\.launchModel), ["sonnet", "gpt-5.5"])
        XCTAssertTrue(launch.prompts.prompts.isEmpty)
        try await launch.wait { await launch.worker.inspectionCount == 2 }
        let task = launch.coordinator.scheduledTaskForTesting(conversationID: conversationID)
        gate.open()
        await task?.value
        XCTAssertEqual(launch.coordinator.runs[conversationID]?.phase, .staged)
        let conversation = try XCTUnwrap(launch.sidebar.context.resolveConversation(conversationID: conversationID))
        let proposal = try XCTUnwrap(try conversation.pullRequestReviewProposal())
        XCTAssertEqual(proposal.stagedComments.count, 1)
        XCTAssertEqual(proposal.stagedComments.first?.body, "**[P2]** A concrete problem.")
        XCTAssertTrue(launch.host.pullRequests.submittedReviews.isEmpty)
        XCTAssertTrue(launch.host.pullRequests.submittedPendingReviews.isEmpty)
    }

    func testExactReviewLaunchRetryReplaysAfterServiceRecreation() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()

        let first = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)
        launch.replaceHostService()
        let replay = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertFalse(first.isError, first.text)
        XCTAssertEqual(replay.text, first.text)
        XCTAssertEqual(replay.structuredContent, first.structuredContent)
        XCTAssertEqual(launch.prompts.prompts.count, 1)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 2)
    }

    func testExactTeamReviewRetryReplaysAfterProposalStaging() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        launch.host.settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
        await launch.worker.configure(empty: true)

        let first = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)
        let conversationID = try XCTUnwrap(try launch.reviewThread().soleMainConversation?.id)
        await launch.coordinator.scheduledTaskForTesting(conversationID: conversationID)?.value
        launch.replaceHostService()
        let replay = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertFalse(first.isError, first.text)
        XCTAssertEqual(launch.coordinator.runs[conversationID]?.phase, .staged)
        XCTAssertEqual(replay.structuredContent, first.structuredContent)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 2)
    }

    func testConcurrentExactReviewLaunchRetriesOnlyDispatchOnce() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        let gate = PullRequestsServiceGate()
        launch.host.pullRequests.detailGate = gate
        let first = Task { await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName) }
        defer { gate.open() }
        try await launch.wait { launch.host.pullRequests.detailCallCount == 1 }
        let replay = Task { await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName) }
        gate.open()

        let firstResult = await first.value
        let replayResult = await replay.value

        XCTAssertFalse(firstResult.isError, firstResult.text)
        XCTAssertEqual(replayResult.structuredContent, firstResult.structuredContent)
        XCTAssertEqual(launch.prompts.prompts.count, 1)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 2)
    }

    func testExistingPersistedPausedAndInterruptedTeamReviewsAreReturnedWithoutDispatch() async throws {
        for phase in [ReviewTeamRun.Phase.awaitingDecision, .interrupted] {
            let launch = try PullRequestHostReviewLaunchFixture()
            launch.host.settingsService.update { $0.pullRequestReviewMode = .reviewTeam }
            let identifier = try XCTUnwrap(PullRequestHostToolFixture.identifier)
            let sourceConversation = launch.host.conversation
            let run = ReviewTeamRun(
                payloadVersion: 1, id: "existing-run", proposalID: "existing-proposal", conversationID: sourceConversation.id,
                identifier: identifier, url: PullRequestHostToolService.fallbackURL(for: identifier), team: reviewTestTeam(),
                criteria: "Original criteria.", priorProposal: try launch.coordinator.staging.snapshot(for: identifier, editState: nil),
                createdAt: .now, generation: 0, phase: phase, inspections: [:], voteReports: [:], accepted: [],
                attempts: [:], failures: [:], supersededProposalIDs: []
            )
            try sourceConversation.storeCollectiveReviewRun(run)
            try launch.sidebar.context.save()
            let persistedRun = sourceConversation.pullRequestReviewRunJSON

            let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

            XCTAssertFalse(result.isError, result.text)
            let content = try object(result.structuredContent)
            XCTAssertEqual(content["status"], .string("existing"))
            XCTAssertEqual(content["thread_id"], .string(sourceConversation.id))
            XCTAssertEqual(content["run_id"], .string(run.id))
            XCTAssertEqual(content["phase"], .string(phase.rawValue))
            XCTAssertEqual(sourceConversation.pullRequestReviewRunJSON, persistedRun)
            XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
            XCTAssertTrue(launch.prompts.prompts.isEmpty)
            let calls = await launch.worker.calls
            XCTAssertTrue(calls.isEmpty)
        }
    }
}
