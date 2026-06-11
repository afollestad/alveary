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

    func testSidebarItemIsThreadOnlyForThreadCase() throws {
        let fixture = try makeFixture(
            primaryConversations: [Conversation(title: "Main", provider: "claude")]
        )
        let project = try XCTUnwrap(fixture.primaryThread.project)

        XCTAssertTrue(SidebarItem.thread(fixture.primaryThread).isThread)
        XCTAssertFalse(SidebarItem.project(project).isThread)
        XCTAssertFalse(SidebarItem.skills.isThread)
        XCTAssertFalse(SidebarItem.mcp.isThread)
        XCTAssertFalse(SidebarItem.settings.isThread)
    }

    func testSelectedConversationIsPureRead() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true, displayOrder: 1)
        let sideConversation = Conversation(title: "Side", provider: "claude", isMain: false, displayOrder: 2)
        let fixture = try makeFixture(primaryConversations: [sideConversation, mainConversation])
        let state = AppState()

        let selectedConversation = state.selectedConversation(
            in: fixture.primaryThread,
            conversations: fixture.primaryConversations
        )

        XCTAssertEqual(selectedConversation?.persistentModelID, mainConversation.persistentModelID)
        XCTAssertTrue(state.selectedConversationIDs.isEmpty)
    }

    func testSelectedConversationUsesStableIDTieBreaker() throws {
        let laterID = Conversation(id: "b", title: "Later", provider: "claude", isMain: false, displayOrder: 1)
        let earlierID = Conversation(id: "a", title: "Earlier", provider: "claude", isMain: false, displayOrder: 1)
        let fixture = try makeFixture(primaryConversations: [laterID, earlierID])
        let state = AppState()

        let selectedConversation = state.selectedConversation(
            in: fixture.primaryThread,
            conversations: fixture.primaryConversations
        )

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
        state.repairSelectedConversationIfNeeded(
            for: fixture.primaryThread,
            conversations: fixture.primaryConversations
        )

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
        state.repairSelectedConversationIfNeeded(
            for: fixture.primaryThread,
            conversations: fixture.primaryConversations
        )

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
        state.repairSelectedConversationIfNeeded(
            for: fixture.primaryThread,
            conversations: fixture.primaryConversations
        )

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

    func testPendingComposerFocusTokenDefaultsToNilUntilRequested() {
        let state = AppState()

        XCTAssertNil(state.pendingComposerFocusToken)
    }

    func testRequestComposerFocusProducesFreshTokenEachCall() {
        let state = AppState()

        state.requestComposerFocus()
        let firstToken = state.pendingComposerFocusToken

        state.requestComposerFocus()
        let secondToken = state.pendingComposerFocusToken

        XCTAssertNotNil(firstToken)
        XCTAssertNotNil(secondToken)
        XCTAssertNotEqual(firstToken, secondToken)
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

    func testRightPaneVisibilityHelpersDriveProgrammaticDrawerState() {
        let state = AppState()

        XCTAssertFalse(state.isRightPaneVisible)

        state.showRightPane()
        XCTAssertTrue(state.isRightPaneVisible)

        state.toggleRightPane()
        XCTAssertFalse(state.isRightPaneVisible)

        state.toggleRightPane()
        XCTAssertTrue(state.isRightPaneVisible)

        state.hideRightPane()
        XCTAssertFalse(state.isRightPaneVisible)
    }

    func testLeftPaneVisibilityHelperMirrorsProvidedBoolean() {
        let state = AppState()

        XCTAssertTrue(state.isLeftPaneVisible)

        state.setLeftPaneVisible(false)
        XCTAssertFalse(state.isLeftPaneVisible)

        state.setLeftPaneVisible(true)
        XCTAssertTrue(state.isLeftPaneVisible)
    }

    func testPresentUnexpectedErrorStoresOldestToNewest() {
        let state = AppState()
        let firstID = UUID()
        let secondID = UUID()

        state.presentUnexpectedError(message: "First", id: firstID)
        state.presentUnexpectedError(message: "Second", id: secondID)

        XCTAssertEqual(state.unexpectedErrorToasts, [
            AppState.UnexpectedErrorToast(id: firstID, message: "First"),
            AppState.UnexpectedErrorToast(id: secondID, message: "Second")
        ])
    }

    func testPresentUnexpectedErrorKeepsNewestThreeRecords() {
        let state = AppState()
        let ids = (0..<4).map { _ in UUID() }

        for index in ids.indices {
            state.presentUnexpectedError(message: "Toast \(index)", id: ids[index])
        }

        XCTAssertEqual(state.unexpectedErrorToasts.map(\.id), Array(ids.suffix(3)))
        XCTAssertEqual(state.unexpectedErrorToasts.map(\.message), ["Toast 1", "Toast 2", "Toast 3"])
    }

    func testDismissUnexpectedErrorToastRemovesOnlyMatchingIdentifier() {
        let state = AppState()
        let firstID = UUID()
        let secondID = UUID()

        state.presentUnexpectedError(message: "First", id: firstID)
        state.presentUnexpectedError(message: "Second", id: secondID)
        state.dismissUnexpectedErrorToast(id: firstID)

        XCTAssertEqual(state.unexpectedErrorToasts, [
            AppState.UnexpectedErrorToast(id: secondID, message: "Second")
        ])
    }

    func testDismissUnexpectedErrorToastIgnoresStaleIdentifierAfterPruning() {
        let state = AppState()
        let ids = (0..<4).map { _ in UUID() }

        for index in ids.indices {
            state.presentUnexpectedError(message: "Toast \(index)", id: ids[index])
        }
        let beforeDismiss = state.unexpectedErrorToasts

        state.dismissUnexpectedErrorToast(id: ids[0])

        XCTAssertEqual(state.unexpectedErrorToasts, beforeDismiss)
    }

    func testDismissingOldestToastPreservesRemainingStoredOrder() {
        let state = AppState()
        let ids = (0..<3).map { _ in UUID() }

        for index in ids.indices {
            state.presentUnexpectedError(message: "Toast \(index)", id: ids[index])
        }

        state.dismissUnexpectedErrorToast(id: ids[0])

        XCTAssertEqual(state.unexpectedErrorToasts.map(\.message), ["Toast 1", "Toast 2"])
    }

    func testErrorToastStackDisplaysNewestToOldest() {
        let state = AppState()

        state.presentUnexpectedError(message: "Oldest", id: UUID())
        state.presentUnexpectedError(message: "Middle", id: UUID())
        state.presentUnexpectedError(message: "Newest", id: UUID())

        let stack = AppErrorToastStack(toasts: state.unexpectedErrorToasts, onDismiss: { _ in })

        XCTAssertEqual(stack.displayToasts.map(\.message), ["Newest", "Middle", "Oldest"])
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
