import AppKit
import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class ThreadDetailViewProjectTrustTests: XCTestCase {
    func testUninitializedThreadHidesConversationStrip() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        XCTAssertFalse(fixture.view.shouldShowConversationStrip(conversationCount: fixture.view.conversations.count))
    }

    func testUninitializedThreadEmptyStateDoesNotOfferInertCreateAction() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        XCTAssertFalse(fixture.view.canCreateConversationFromEmptyState)
    }

    func testInitializedRealThreadEmptyStateOffersCreateAction() throws {
        let fixture = try ThreadDetailProjectTrustFixture(hasCompletedInitialSetup: true)

        XCTAssertTrue(fixture.view.canCreateConversationFromEmptyState)
    }

    func testDraftEmptyConversationStateDoesNotPersistRestoreSelection() throws {
        let fixture = try ThreadDetailProjectTrustFixture(isDraft: true)

        XCTAssertFalse(fixture.view.canPersistEmptyConversationSelection)
    }

    func testHostedCloseShortcutWithStripAbsentConsumesSingleConversationWithoutRemovingOrClosingWindow() throws {
        let fixture = try ThreadDetailProjectTrustFixture()
        var removedConversationIDs: [PersistentIdentifier] = []
        let host = HostedConversationCloseShortcut(
            conversations: [fixture.conversation],
            selectedConversation: fixture.conversation,
            isRenaming: false
        ) { removedConversationIDs.append($0.persistentModelID) }
        defer { host.close() }

        XCTAssertTrue(try host.performCommandW())
        XCTAssertTrue(removedConversationIDs.isEmpty)
        XCTAssertEqual(host.closeRequestCount, 0)
        XCTAssertTrue(host.isWindowVisible)
    }

    func testHostedCloseShortcutWithStripAbsentConsumesRenameWithoutRemovingOrClosingWindow() throws {
        let fixture = try ThreadDetailProjectTrustFixture()
        let sideConversation = Conversation(
            id: "side",
            title: "Side",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: fixture.thread
        )
        var removedConversationIDs: [PersistentIdentifier] = []
        let host = HostedConversationCloseShortcut(
            conversations: [fixture.conversation, sideConversation],
            selectedConversation: sideConversation,
            isRenaming: true
        ) { removedConversationIDs.append($0.persistentModelID) }
        defer { host.close() }

        XCTAssertTrue(try host.performCommandW())
        XCTAssertTrue(removedConversationIDs.isEmpty)
        XCTAssertEqual(host.closeRequestCount, 0)
        XCTAssertTrue(host.isWindowVisible)
    }

    func testHostedCloseShortcutWithStripAbsentRemovesSelectedConversationWhenMultipleExist() throws {
        let fixture = try ThreadDetailProjectTrustFixture()
        let sideConversation = Conversation(
            id: "side",
            title: "Side",
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: fixture.thread
        )
        var removedConversationIDs: [PersistentIdentifier] = []
        let host = HostedConversationCloseShortcut(
            conversations: [fixture.conversation, sideConversation],
            selectedConversation: sideConversation,
            isRenaming: false
        ) { removedConversationIDs.append($0.persistentModelID) }
        defer { host.close() }

        XCTAssertTrue(try host.performCommandW())
        XCTAssertEqual(removedConversationIDs, [sideConversation.persistentModelID])
        XCTAssertEqual(host.closeRequestCount, 0)
        XCTAssertTrue(host.isWindowVisible)
    }

    func testTransientEmptyConversationFetchPreservesSelectedConversation() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        let resolved = ThreadDetailConversationResolver.resolve(
            fetchedConversations: [],
            thread: fixture.thread,
            selectedConversationID: fixture.conversation.persistentModelID,
            modelContext: fixture.context
        )

        XCTAssertEqual(resolved.map(\.persistentModelID), [fixture.conversation.persistentModelID])
    }

    func testTransientEmptyConversationFetchFallsBackToSecondaryFetch() throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        let resolved = ThreadDetailConversationResolver.resolve(
            fetchedConversations: nil,
            thread: fixture.thread,
            selectedConversationID: nil,
            modelContext: fixture.context
        )

        XCTAssertEqual(resolved.map(\.persistentModelID), [fixture.conversation.persistentModelID])
    }

    func testStaleTrustCheckCannotAutoTrustPreviousDraftProjectAfterReassignment() async throws {
        let originalPath = "/tmp/alveary-project"
        let replacementPath = "/tmp/reassigned-project"
        let providerSetup = PausingThreadDetailProjectTrustService(pausedProjectPath: originalPath)
        var settings = AppSettings()
        settings.autoTrustProjects = true
        let fixture = try ThreadDetailProjectTrustFixture(
            isDraft: true,
            settings: settings,
            providerSetup: providerSetup
        )

        let originalRefresh = Task { @MainActor in
            await fixture.view.refreshProjectTrustPrompt(for: fixture.conversation)
        }
        await providerSetup.waitUntilStatusPaused()

        let replacementProject = Project(path: replacementPath, name: "Reassigned")
        fixture.context.insert(replacementProject)
        fixture.thread.project = replacementProject
        try fixture.context.save()

        await fixture.view.refreshProjectTrustPrompt(for: fixture.conversation)
        await providerSetup.resumePausedStatus()
        await originalRefresh.value

        let trustedProjectPaths = await providerSetup.recordedTrustedProjectPaths()
        XCTAssertEqual(trustedProjectPaths, [CanonicalPath.normalize(replacementPath)])
        XCTAssertNil(fixture.view.projectTrustPrompt)
        XCTAssertFalse(fixture.view.isCheckingProjectTrust)
    }

    func testDenyProjectTrustRoutesThroughInjectedThreadDelete() async throws {
        let fixture = try ThreadDetailProjectTrustFixture()

        await fixture.view.denyProjectTrust(fixture.prompt)

        let deletedThreadIDs = fixture.deleteRecorder.deletedThreadIDs
        XCTAssertEqual(deletedThreadIDs, [fixture.thread.persistentModelID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 0)
        XCTAssertEqual(fixture.appState.selectedSidebarItem, .project(fixture.project))
        XCTAssertNil(fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID])
    }

    func testDenyProjectTrustDoesNotRollbackSelectionForPostCommitCleanupFailure() async throws {
        let fixture = try ThreadDetailProjectTrustFixture(deleteError: SidebarViewModelError.threadDeleteCleanupFailed(
            ThreadDetailProjectTrustError.cleanupFailed
        ))

        await fixture.view.denyProjectTrust(fixture.prompt)

        XCTAssertEqual(fixture.appState.selectedSidebarItem, .project(fixture.project))
        XCTAssertNil(fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID])
        XCTAssertEqual(
            fixture.appState.unexpectedErrorToasts.map(\.message),
            ["Thread was deleted, but cleanup failed: Cleanup failed"]
        )
    }

    func testDenyProjectTrustRollsBackSelectionForPreCommitDeleteFailure() async throws {
        let fixture = try ThreadDetailProjectTrustFixture(
            deleteError: ThreadDetailProjectTrustError.cleanupFailed,
            deletesBeforeThrowing: false
        )

        await fixture.view.denyProjectTrust(fixture.prompt)

        XCTAssertEqual(fixture.appState.selectedSidebarItem, .thread(fixture.thread))
        XCTAssertEqual(fixture.appState.previousSelection, .threadId(fixture.thread.persistentModelID))
        XCTAssertEqual(fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID], fixture.conversation.persistentModelID)
        XCTAssertEqual(fixture.deleteRecorder.deletedThreadIDs, [fixture.thread.persistentModelID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
    }

    func testDenyProjectTrustFailureDoesNotRestoreSelectionUnderVoiceModelModal() async throws {
        let fixture = try ThreadDetailProjectTrustFixture(
            deleteError: ThreadDetailProjectTrustError.cleanupFailed,
            deletesBeforeThrowing: false
        )
        let modalSink = ThreadDetailVoiceModelModalSink()
        fixture.view.voiceInputLifecycleController.setActiveComposerSink(modalSink)

        await fixture.view.denyProjectTrust(fixture.prompt)

        XCTAssertEqual(fixture.appState.selectedSidebarItem, .project(fixture.project))
        XCTAssertEqual(fixture.appState.previousSelection, .threadId(fixture.thread.persistentModelID))
        XCTAssertNil(fixture.appState.selectedConversationIDs[fixture.thread.persistentModelID])
        XCTAssertEqual(try fixture.context.fetchCount(FetchDescriptor<AgentThread>()), 1)
    }
}

@MainActor
final class HostedConversationCloseShortcut {
    private let controller: NSHostingController<AnyView>
    private let closeRecorder: ConversationCloseWindowDelegate
    private let window: NSWindow

    var closeRequestCount: Int { closeRecorder.closeRequestCount }
    var isWindowVisible: Bool { window.isVisible }

    init(
        conversations: [Conversation],
        selectedConversation: Conversation?,
        isRenaming: Bool,
        canRemove: @escaping (Conversation) -> Bool = { _ in true },
        onRemove: @escaping (Conversation) -> Void
    ) {
        let rootView = ConversationCloseShortcutSink(
            conversations: conversations,
            selectedConversation: selectedConversation,
            isRenaming: isRenaming,
            canRemove: canRemove,
            onRemove: onRemove
        )
        .frame(width: 320, height: 180)
        controller = NSHostingController(rootView: AnyView(rootView))
        controller.view.frame = NSRect(x: 0, y: 0, width: 320, height: 180)

        let window = NSWindow(
            contentRect: NSRect(x: -1320, y: -1180, width: 320, height: 180),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        let closeRecorder = ConversationCloseWindowDelegate()
        self.closeRecorder = closeRecorder
        self.window = window
        window.delegate = closeRecorder
        window.isReleasedWhenClosed = false
        window.contentViewController = controller
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(controller.view)
        window.layoutIfNeeded()
        window.displayIfNeeded()
        controller.view.layoutSubtreeIfNeeded()
        controller.view.displayIfNeeded()
    }

    func performCommandW() throws -> Bool {
        let event = try XCTUnwrap(NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: .command,
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            characters: "w",
            charactersIgnoringModifiers: "w",
            isARepeat: false,
            keyCode: 13
        ))
        return window.performKeyEquivalent(with: event)
    }

    func close() {
        window.delegate = nil
        window.orderOut(nil)
        window.close()
    }
}

private final class ConversationCloseWindowDelegate: NSObject, NSWindowDelegate {
    private(set) var closeRequestCount = 0

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        closeRequestCount += 1
        return true
    }
}
