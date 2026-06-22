import AgentCLIKit
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testStartGoalBeforeSetupSpawnsWithInitialGoal() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false,
            providerId: "codex"
        )
        fixture.viewModel.setGoalModeArmed(true)

        try await fixture.viewModel.startGoal("Ship goal mode")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        XCTAssertEqual(spawnCalls.count, 1)
        XCTAssertEqual(spawnCalls.first?.config.initialPrompt, "Ship goal mode")
        XCTAssertEqual(spawnCalls.first?.config.initialGoal, "Ship goal mode")
        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        XCTAssertTrue(goalStartCalls.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Ship goal mode"])
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testStartGoalAfterHiddenSetupUsesDedicatedGoalStartSend() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.viewModel.setGoalModeArmed(true)

        try await fixture.viewModel.startGoal("Refactor the cache")

        let spawnCalls = await fixture.agentsManager.spawnCalls()
        let sentMessages = await fixture.agentsManager.sentMessages()
        let sendVisibilities = await fixture.agentsManager.sendVisibilities()
        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        XCTAssertTrue(spawnCalls.isEmpty)
        XCTAssertEqual(sentMessages, ["Refactor the cache"])
        XCTAssertEqual(sendVisibilities, [.visible])
        XCTAssertEqual(goalStartCalls, [
            .init(
                message: "Refactor the cache",
                initialGoal: "Refactor the cache",
                conversationId: fixture.conversation.id,
                activityVisibility: .visible
            )
        ])
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Refactor the cache"])
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testFailedGoalStartRemovesAttemptAndKeepsGoalModeArmed() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: false,
            initialAgentIsRunning: false
        )
        fixture.viewModel.setGoalModeArmed(true)
        await fixture.agentsManager.enqueueSpawnError(MockAgentsManager.MockError.sendFailed)

        do {
            try await fixture.viewModel.startGoal("Ship goal mode")
            XCTFail("Expected goal start to fail.")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        XCTAssertTrue(try fixture.userMessages().isEmpty)
        XCTAssertTrue(fixture.viewModel.state.retryableFailedMessageIDs.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertNotNil(fixture.viewModel.lastTurnError)
    }

    func testDisarmingGoalModePreservesDraft() throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.replaceInputDraft("Ship goal mode", source: .legacyText)
        fixture.viewModel.setGoalModeArmed(true)

        fixture.viewModel.disarmGoalModeIfNeeded()

        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
        XCTAssertEqual(fixture.viewModel.state.inputDraft, "Ship goal mode")
    }

    func testGoalEventsPersistHydrateAndDismissTerminalStatus() throws {
        let fixture = try ConversationViewModelTestFixture()
        let active = AgentGoalSnapshot(
            objective: "Ship goal mode",
            status: .active,
            availableActions: [.pause, .delete],
            elapsedSeconds: 15
        )
        let achieved = AgentGoalSnapshot(
            objective: "Ship goal mode",
            status: .achieved,
            elapsedSeconds: 42
        )

        fixture.viewModel.handleEvent(.goal(.init(snapshot: active)))
        fixture.viewModel.handleEvent(.goal(.init(snapshot: achieved)))
        XCTAssertEqual(fixture.viewModel.visibleGoalSnapshot, achieved)

        fixture.viewModel.dismissTerminalGoalStatus()

        let goalRecords = try fixture.records(type: ConversationEventRecord.goalType)
        XCTAssertEqual(goalRecords.count, 3)
        XCTAssertTrue(goalRecords.allSatisfy(\.isHiddenGoalRecord))
        XCTAssertTrue(goalRecords.allSatisfy { !$0.isVisibleTranscriptEvent })
        XCTAssertNil(fixture.viewModel.visibleGoalSnapshot)

        fixture.viewModel.state.goalSnapshot = nil
        fixture.viewModel.state.dismissedTerminalGoalKeys.removeAll()
        fixture.viewModel.hydrateGoalState(from: goalRecords)

        XCTAssertEqual(fixture.viewModel.state.goalSnapshot, achieved)
        XCTAssertNil(fixture.viewModel.visibleGoalSnapshot)
        XCTAssertEqual(try fixture.records(type: ConversationEventRecord.goalType).count, 3)
    }

    func testRuntimeGoalStatusPersistsHiddenSnapshotDuringHydration() throws {
        let fixture = try ConversationViewModelTestFixture()
        let snapshot = AgentGoalSnapshot(
            objective: "Persist runtime status",
            status: .active,
            availableActions: [.delete]
        )
        fixture.viewModel.state.goalSnapshot = snapshot

        let records = try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).filter {
            $0.conversationId == fixture.conversation.id
        }
        fixture.viewModel.rebuildChatItemsIfNeeded(from: records)

        let goalRecords = try fixture.records(type: ConversationEventRecord.goalType)
        XCTAssertEqual(goalRecords.count, 1)
        XCTAssertEqual(goalRecords.first?.content, "Persist runtime status")
        XCTAssertTrue(goalRecords.allSatisfy(\.isHiddenGoalRecord))
    }
}
