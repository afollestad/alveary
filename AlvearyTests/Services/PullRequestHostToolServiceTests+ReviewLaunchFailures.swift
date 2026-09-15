import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension PullRequestHostToolServiceTests {
    func testReviewLaunchRejectsInvalidArgumentsAndMissingRequestIdentityBeforeFetching() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        let arguments: [[String: AgentCLIKit.JSONValue]] = [
            [:],
            ["url": .string("https://example.com/not-a-pr")],
            ["url": .string(PullRequestHostToolFixture.url), "review_mode": .string("singleAgent")],
            ["url": .string(PullRequestHostToolFixture.url), "provider": .string("codex")]
        ]
        for arguments in arguments {
            let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName, arguments: arguments)
            XCTAssertTrue(result.isError, result.text)
            XCTAssertEqual(try object(result.structuredContent)["status"], .string("error"))
        }
        let missingIdentity = await launch.host.handle(
            PullRequestHostToolCatalog.startReviewToolName, context: launch.host.agentContext(requestID: nil)
        )

        XCTAssertEqual(missingIdentity.text, PullRequestHostToolServiceError.missingRequestIdentity.localizedDescription)
        XCTAssertEqual(launch.host.pullRequests.detailCallCount, 0)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertTrue(launch.prompts.prompts.isEmpty)
    }

    func testReviewLaunchRejectsHarnessMismatchBeforeFetching() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()

        let result = await launch.host.handle(
            PullRequestHostToolCatalog.startReviewToolName, context: launch.host.agentContext(harnessID: .claude)
        )

        XCTAssertEqual(result.text, PullRequestHostToolServiceError.sourceHarnessMismatch.localizedDescription)
        XCTAssertEqual(launch.host.pullRequests.detailCallCount, 0)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
    }

    func testReviewLaunchRevalidatesSourceAndIntegrationAfterFetching() async throws {
        for disableIntegration in [false, true] {
            let launch = try PullRequestHostReviewLaunchFixture()
            let gate = PullRequestsServiceGate()
            defer { gate.open() }
            launch.host.pullRequests.detailGate = gate
            let call = Task { await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName) }
            try await launch.wait { launch.host.pullRequests.detailCallCount == 1 }
            if disableIntegration {
                launch.host.settingsService.update { $0.pullRequestsEnabled = false }
            } else {
                launch.host.thread.archivedAt = .now
                try launch.sidebar.context.save()
            }
            gate.open()

            let result = await call.value

            let expected: PullRequestHostToolServiceError = disableIntegration ? .pullRequestsDisabled : .sourceConversationUnavailable
            XCTAssertEqual(result.text, expected.localizedDescription)
            XCTAssertTrue(result.isError)
            XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
            XCTAssertTrue(launch.prompts.prompts.isEmpty)
        }
    }

    func testCancelledReviewLaunchCreatesNoTaskAfterFetchingResumes() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        let gate = PullRequestsServiceGate()
        defer { gate.open() }
        launch.host.pullRequests.detailGate = gate
        let call = Task { await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName) }
        try await launch.wait { launch.host.pullRequests.detailCallCount == 1 }
        call.cancel()
        gate.open()

        let result = await call.value

        XCTAssertTrue(result.isError)
        XCTAssertTrue(result.text.contains("cancelled"), result.text)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertTrue(launch.prompts.prompts.isEmpty)
    }

    func testInvalidSavedReviewTeamReportsTheSettingFailureBeforeCreatingTask() async throws {
        let launch = try PullRequestHostReviewLaunchFixture()
        launch.host.settingsService.update {
            $0.pullRequestReviewMode = .reviewTeam
            $0.pullRequestReviewPeers = []
        }

        let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertTrue(result.isError)
        XCTAssertEqual(result.text, PullRequestReviewTeamResolutionError.invalidTeamSize(1).localizedDescription)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
        XCTAssertTrue(launch.coordinator.runs.isEmpty)
        let calls = await launch.worker.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testReviewLaunchReceiptFailurePreventsDispatchAndReturnsTheCreatedDestination() async throws {
        let launch = try PullRequestHostReviewLaunchFixture(receiptSave: { _ in throw CocoaError(.fileWriteUnknown) })

        let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)
        let replay = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertTrue(result.isError)
        let content = try object(result.structuredContent)
        let destination = try launch.reviewThread()
        XCTAssertEqual(content["status"], .string("error"))
        XCTAssertEqual(content["thread_id"], destination.soleMainConversation.map { .string($0.id) })
        XCTAssertEqual(replay.structuredContent, result.structuredContent)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 2)
        XCTAssertTrue(launch.prompts.prompts.isEmpty)
        XCTAssertTrue(launch.coordinator.runs.isEmpty)
    }

    func testReviewLaunchDispatchFailureRetainsDestinationAndReplaysWithoutRestarting() async throws {
        let launch = try PullRequestHostReviewLaunchFixture(coordinatorSave: { _ in throw CocoaError(.fileWriteUnknown) })
        launch.host.settingsService.update { $0.pullRequestReviewMode = .reviewTeam }

        let result = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)
        launch.replaceHostService()
        let replay = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertTrue(result.isError)
        let content = try object(result.structuredContent)
        XCTAssertEqual(content["status"], .string("error"))
        XCTAssertNotNil(content["thread_id"])
        XCTAssertEqual(replay.structuredContent, result.structuredContent)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 2)
        let calls = await launch.worker.calls
        XCTAssertTrue(calls.isEmpty)
    }

    func testPendingDestinationReceiptResumesWithoutDispatchingTwiceAfterFinalSaveFailure() async throws {
        var saveCount = 0
        let launch = try PullRequestHostReviewLaunchFixture(receiptSave: { context in
            saveCount += 1
            guard saveCount == 1 else { throw CocoaError(.fileWriteUnknown) }
            try context.save()
        })

        let failed = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)
        launch.replaceHostService()
        let replay = await launch.host.handle(PullRequestHostToolCatalog.startReviewToolName)

        XCTAssertTrue(failed.isError)
        XCTAssertFalse(replay.isError, replay.text)
        XCTAssertEqual(try object(replay.structuredContent)["status"], .string("started"))
        XCTAssertEqual(try object(replay.structuredContent)["thread_id"], try object(failed.structuredContent)["thread_id"])
        XCTAssertEqual(launch.prompts.prompts.count, 1)
        XCTAssertEqual(try launch.sidebar.context.fetchCount(FetchDescriptor<AgentThread>()), 2)
    }
}
