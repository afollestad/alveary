import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class AppStateTests: XCTestCase {
    func testOpenSettingsPreservesPreviousSelectionUntilLeavingSettings() throws {
        let fixture = try makeFixture(
            primaryConversations: [Conversation(title: "Main", provider: "claude")]
        )
        let state = AppState()

        state.selectedSidebarItem = .thread(fixture.primaryThread)
        state.openSettings()

        XCTAssertEqual(state.previousSelection, AppState.SidebarBookmark.threadId(fixture.primaryThread.persistentModelID))
        XCTAssertEqual(state.selectedSidebarItem, .settings)

        state.openSettings()

        XCTAssertEqual(state.previousSelection, AppState.SidebarBookmark.threadId(fixture.primaryThread.persistentModelID))
    }

    func testSelectedConversationIsPureRead() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true, displayOrder: 1)
        let sideConversation = Conversation(title: "Side", provider: "claude", isMain: false, displayOrder: 2)
        let fixture = try makeFixture(primaryConversations: [sideConversation, mainConversation])
        let state = AppState()

        let selectedConversation = state.selectedConversation(in: fixture.primaryThread)

        XCTAssertEqual(selectedConversation?.persistentModelID, mainConversation.persistentModelID)
        XCTAssertTrue(state.selectedConversationIDs.isEmpty)
    }

    func testSelectedConversationUsesStableIDTieBreaker() throws {
        let laterID = Conversation(id: "b", title: "Later", provider: "claude", isMain: false, displayOrder: 1)
        let earlierID = Conversation(id: "a", title: "Earlier", provider: "claude", isMain: false, displayOrder: 1)
        let fixture = try makeFixture(primaryConversations: [laterID, earlierID])
        let state = AppState()

        let selectedConversation = state.selectedConversation(in: fixture.primaryThread)

        XCTAssertEqual(selectedConversation?.id, earlierID.id)
    }

    func testRepairSelectedConversationFallsBackToMainConversation() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true, displayOrder: 2)
        let otherConversation = Conversation(title: "Other", provider: "claude", isMain: false, displayOrder: 1)
        let wrongConversation = Conversation(title: "Wrong", provider: "claude")
        let fixture = try makeFixture(
            primaryConversations: [mainConversation, otherConversation],
            secondaryConversations: [wrongConversation]
        )
        let state = AppState()

        state.selectedConversationIDs[fixture.primaryThread.persistentModelID] = wrongConversation.persistentModelID
        state.repairSelectedConversationIfNeeded(for: fixture.primaryThread)

        XCTAssertEqual(
            state.selectedConversationIDs[fixture.primaryThread.persistentModelID],
            mainConversation.persistentModelID
        )
    }

    func testRepairSelectedConversationFallsBackToFirstDisplayOrderWhenNoMainConversationExists() throws {
        let firstConversation = Conversation(title: "First", provider: "claude", isMain: false, displayOrder: 1)
        let laterConversation = Conversation(title: "Later", provider: "claude", isMain: false, displayOrder: 4)
        let wrongConversation = Conversation(title: "Wrong", provider: "claude")
        let fixture = try makeFixture(
            primaryConversations: [laterConversation, firstConversation],
            secondaryConversations: [wrongConversation]
        )
        let state = AppState()

        state.selectedConversationIDs[fixture.primaryThread.persistentModelID] = wrongConversation.persistentModelID
        state.repairSelectedConversationIfNeeded(for: fixture.primaryThread)

        XCTAssertEqual(
            state.selectedConversationIDs[fixture.primaryThread.persistentModelID],
            firstConversation.persistentModelID
        )
    }

    func testRepairSelectedConversationRemovesBookmarkWhenThreadHasNoConversations() throws {
        let wrongConversation = Conversation(title: "Wrong", provider: "claude")
        let fixture = try makeFixture(
            primaryConversations: [],
            secondaryConversations: [wrongConversation]
        )
        let state = AppState()

        state.selectedConversationIDs[fixture.primaryThread.persistentModelID] = wrongConversation.persistentModelID
        state.repairSelectedConversationIfNeeded(for: fixture.primaryThread)

        XCTAssertNil(state.selectedConversationIDs[fixture.primaryThread.persistentModelID])
    }

    func testSelectConversationOnlyClearsDiffActionWhenSelectingAwayFromTargetConversation() throws {
        let targetConversation = Conversation(title: "Target", provider: "claude", isMain: true, displayOrder: 0)
        let otherConversation = Conversation(title: "Other", provider: "claude", isMain: false, displayOrder: 1)
        let fixture = try makeFixture(primaryConversations: [targetConversation, otherConversation])
        let state = AppState()

        state.pendingDiffAction = AppState.DiffActionRequest(
            id: UUID(),
            conversationID: targetConversation.persistentModelID,
            message: "Generate commit"
        )
        state.selectConversation(targetConversation, in: fixture.primaryThread)

        XCTAssertNotNil(state.pendingDiffAction)

        state.selectConversation(otherConversation, in: fixture.primaryThread)

        XCTAssertNil(state.pendingDiffAction)
        XCTAssertEqual(
            state.selectedConversationIDs[fixture.primaryThread.persistentModelID],
            otherConversation.persistentModelID
        )
    }

    func testRequestDiffActionAlwaysReplacesExistingRequestWithFreshIdentifier() throws {
        let conversation = try makeFixture(
            primaryConversations: [Conversation(title: "Main", provider: "claude")]
        ).primaryConversations[0]
        let state = AppState()

        state.requestDiffAction(message: "Open a PR", conversationID: conversation.persistentModelID)
        let firstRequest = try XCTUnwrap(state.pendingDiffAction)
        state.requestDiffAction(message: "Open a PR", conversationID: conversation.persistentModelID)
        let secondRequest = try XCTUnwrap(state.pendingDiffAction)

        XCTAssertEqual(secondRequest.message, firstRequest.message)
        XCTAssertEqual(secondRequest.conversationID, firstRequest.conversationID)
        XCTAssertNotEqual(secondRequest.id, firstRequest.id)
    }

    func testTerminalPaneVisibilityHelpersDriveProgrammaticDrawerState() {
        let state = AppState()

        XCTAssertFalse(state.isTerminalPaneVisible)

        state.showTerminalPane()
        XCTAssertTrue(state.isTerminalPaneVisible)

        state.toggleTerminalPane()
        XCTAssertFalse(state.isTerminalPaneVisible)

        state.toggleTerminalPane()
        XCTAssertTrue(state.isTerminalPaneVisible)

        state.hideTerminalPane()
        XCTAssertFalse(state.isTerminalPaneVisible)
    }

    private func makeFixture(
        primaryConversations: [Conversation],
        secondaryConversations: [Conversation] = []
    ) throws -> ThreadFixture {
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)

        let project = Project(path: "/tmp/\(UUID().uuidString)", name: "Fixture")
        let primaryThread = AgentThread(name: "Primary", conversations: primaryConversations)
        project.threads.append(primaryThread)

        if !secondaryConversations.isEmpty {
            let secondaryThread = AgentThread(name: "Secondary", conversations: secondaryConversations)
            project.threads.append(secondaryThread)
        }

        context.insert(project)
        try context.save()

        return ThreadFixture(
            container: container,
            context: context,
            primaryThread: primaryThread,
            primaryConversations: primaryConversations
        )
    }
}

private struct ThreadFixture {
    let container: ModelContainer
    let context: ModelContext
    let primaryThread: AgentThread
    let primaryConversations: [Conversation]
}
