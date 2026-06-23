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

    func testStartGoalInEstablishedThreadUsesExistingSessionGoalStart() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        let existingMessage = ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "message",
            role: "user",
            content: "Earlier request",
            conversation: try fixture.dbConversation()
        )
        fixture.context.insert(existingMessage)
        try fixture.context.save()
        fixture.viewModel.setGoalModeArmed(true)

        try await fixture.viewModel.startGoal(
            "Audit remaining failures",
            supportsExistingSessionGoalStart: true
        )

        let existingGoalStarts = await fixture.agentsManager.existingGoalStartCalls()
        XCTAssertEqual(existingGoalStarts, [
            .init(objective: "Audit remaining failures", conversationId: fixture.conversation.id)
        ])
        let sentMessages = await fixture.agentsManager.sentMessages()
        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        XCTAssertTrue(sentMessages.isEmpty)
        XCTAssertTrue(goalStartCalls.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), ["Earlier request"])
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testEstablishedThreadGoalStartRequiresExistingSessionCapability() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true
        )
        fixture.context.insert(ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "message",
            role: "user",
            content: "Earlier request",
            conversation: try fixture.dbConversation()
        ))
        try fixture.context.save()
        fixture.viewModel.setGoalModeArmed(true)

        do {
            try await fixture.viewModel.startGoal("Audit remaining failures")
            XCTFail("Expected existing-session goal start to be rejected.")
        } catch AgentError.spawnFailed(let message) {
            XCTAssertEqual(message, "This agent can only start Goal mode before the first visible user message.")
        }

        let existingGoalStarts = await fixture.agentsManager.existingGoalStartCalls()
        XCTAssertTrue(existingGoalStarts.isEmpty)
        XCTAssertTrue(fixture.viewModel.state.isGoalModeArmed)
    }

    func testTerminalGoalSnapshotDoesNotBlockLaterGoalStart() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.viewModel.state.goalSnapshot = AgentGoalSnapshot(
            objective: "Old goal",
            status: .achieved,
            elapsedSeconds: 20
        )
        fixture.viewModel.setGoalModeArmed(true)

        try await fixture.viewModel.startGoal("Next goal")

        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        XCTAssertEqual(goalStartCalls.map(\.initialGoal), ["Next goal"])
        XCTAssertFalse(fixture.viewModel.state.isGoalModeArmed)
    }

    func testActiveGoalSnapshotBlocksLaterGoalStart() async throws {
        let fixture = try ConversationViewModelTestFixture(
            hasCompletedInitialSetup: true,
            initialAgentIsRunning: true,
            providerId: "codex"
        )
        fixture.viewModel.state.goalSnapshot = AgentGoalSnapshot(
            objective: "Current goal",
            status: .active,
            availableActions: [.delete]
        )

        do {
            try await fixture.viewModel.startGoal("Next goal")
            XCTFail("Expected active goal to block replacement.")
        } catch AgentError.spawnFailed(let message) {
            XCTAssertEqual(message, "A goal is already active.")
        }

        let goalStartCalls = await fixture.agentsManager.goalStartCalls()
        let existingGoalStarts = await fixture.agentsManager.existingGoalStartCalls()
        XCTAssertTrue(goalStartCalls.isEmpty)
        XCTAssertTrue(existingGoalStarts.isEmpty)
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
