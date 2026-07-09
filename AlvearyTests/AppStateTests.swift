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

    func testOpenSettingsCanTargetOneSettingsPage() throws {
        let fixture = try makeFixture(
            primaryConversations: [Conversation(title: "Main", provider: "claude")]
        )
        let state = AppState()

        state.selectedSidebarItem = .thread(fixture.primaryThread)
        state.openSettings(targetPage: .appUpdates)

        XCTAssertEqual(state.previousSelection, AppState.SidebarBookmark.threadId(fixture.primaryThread.persistentModelID))
        XCTAssertEqual(state.selectedSidebarItem, .settings)
        XCTAssertEqual(state.pendingSettingsTargetPage, .appUpdates)
    }

    func testOpenSettingsWithoutTargetClearsStaleSettingsTarget() {
        let state = AppState()

        state.openSettings(targetPage: .appUpdates)
        state.openSettings()

        XCTAssertEqual(state.selectedSidebarItem, .settings)
        XCTAssertNil(state.pendingSettingsTargetPage)
    }

    func testClearsOnlyMatchingPendingSettingsTargetPage() {
        let state = AppState()

        state.openSettings(targetPage: .appUpdates)
        state.clearPendingSettingsTargetPage(.threads)

        XCTAssertEqual(state.pendingSettingsTargetPage, .appUpdates)

        state.clearPendingSettingsTargetPage(.appUpdates)

        XCTAssertNil(state.pendingSettingsTargetPage)
    }

    func testOpenSettingsCanRetargetAfterPreviousTargetIsHandled() {
        let state = AppState()

        state.openSettings(targetPage: .appUpdates)
        state.clearPendingSettingsTargetPage(.appUpdates)
        state.openSettings(targetPage: .appUpdates)

        XCTAssertEqual(state.selectedSidebarItem, .settings)
        XCTAssertEqual(state.pendingSettingsTargetPage, .appUpdates)
    }

    func testUpdateToolbarBadgeStateTargetsAppUpdatesForActionableStates() {
        XCTAssertNil(AppUpdateToolbarBadgeState.none.settingsTargetPage)
        XCTAssertEqual(AppUpdateToolbarBadgeState.updateAvailable.settingsTargetPage, .appUpdates)
        XCTAssertEqual(AppUpdateToolbarBadgeState.readyToInstall.settingsTargetPage, .appUpdates)
    }

    func testUpdateToolbarBadgeStateUsesReadyToInstallPrecedence() {
        XCTAssertEqual(
            AppUpdateToolbarBadgeState(updateAvailable: true, readyToInstall: true),
            .readyToInstall
        )
        XCTAssertEqual(
            AppUpdateToolbarBadgeState(updateAvailable: true, readyToInstall: false),
            .updateAvailable
        )
        XCTAssertEqual(
            AppUpdateToolbarBadgeState(updateAvailable: false, readyToInstall: false),
            .none
        )
    }

    func testUpdateToolbarBadgeStateAccessibilityValuesDescribeState() {
        XCTAssertEqual(AppUpdateToolbarBadgeState.none.accessibilityValue, "No app update available")
        XCTAssertEqual(AppUpdateToolbarBadgeState.updateAvailable.accessibilityValue, "App update available")
        XCTAssertEqual(AppUpdateToolbarBadgeState.readyToInstall.accessibilityValue, "App update ready to install")
    }

    func testClearsMatchingCommitMessageGenerationRequest() throws {
        let fixture = try makeFixture(
            primaryConversations: [Conversation(title: "Main", provider: "claude")]
        )
        let state = AppState()

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            conversationID: fixture.primaryConversations[0].persistentModelID,
            completion: { _ in }
        )
        let requestID = try XCTUnwrap(state.pendingCommitMessageGenerationRequest?.id)

        state.clearCommitMessageGenerationRequest(id: requestID)

        XCTAssertNil(state.pendingCommitMessageGenerationRequest)
    }

    func testCancelsCommitMessageGenerationRequestWhenSelectedConversationChanges() throws {
        let mainConversation = Conversation(title: "Main", provider: "claude", isMain: true)
        let sideConversation = Conversation(title: "Side", provider: "claude", isMain: false, displayOrder: 2)
        let fixture = try makeFixture(primaryConversations: [mainConversation, sideConversation])
        let state = AppState()
        var capturedError: Error?

        state.requestCommitMessageGeneration(
            prompt: "Generate commit",
            conversationID: mainConversation.persistentModelID,
            completion: { result in
                if case .failure(let error) = result {
                    capturedError = error
                }
            }
        )

        state.selectConversation(sideConversation, in: fixture.primaryThread)

        XCTAssertNil(state.pendingCommitMessageGenerationRequest)
        XCTAssertEqual(
            capturedError?.localizedDescription,
            CommitMessageGenerationError.activeConversationChanged.localizedDescription
        )
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
