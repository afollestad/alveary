import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class ContentViewNotificationRoutingTests: XCTestCase {
    func testOpenConversationSelectsThreadAndConversation() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Thread", archivedAt: nil)

        openConversationInAppState(
            conversationId: conversation.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )

        guard case .thread(let thread) = fixture.appState.selectedSidebarItem else {
            return XCTFail("selectedSidebarItem should resolve to the conversation's thread")
        }
        XCTAssertEqual(thread.persistentModelID, conversation.thread?.persistentModelID)
        XCTAssertEqual(
            fixture.appState.selectedConversationIDs[thread.persistentModelID],
            conversation.persistentModelID
        )
    }

    func testOpenConversationIgnoresArchivedThread() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Archived", archivedAt: Date())

        openConversationInAppState(
            conversationId: conversation.id,
            modelContext: fixture.context,
            appState: fixture.appState
        )

        XCTAssertNil(fixture.appState.selectedSidebarItem)
        XCTAssertTrue(fixture.appState.selectedConversationIDs.isEmpty)
    }

    func testOpenConversationIgnoresMissingConversationId() throws {
        let fixture = try RoutingTestFixture()

        openConversationInAppState(
            conversationId: "missing",
            modelContext: fixture.context,
            appState: fixture.appState
        )

        XCTAssertNil(fixture.appState.selectedSidebarItem)
    }

    func testActiveConversationProviderReturnsNilWhenNoThreadSelected() throws {
        let appState = AppState()
        let provider = makeActiveConversationProvider(for: appState)

        XCTAssertNil(provider())
    }

    func testActiveConversationProviderReturnsSelectedConversationIdForThread() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Thread", archivedAt: nil)
        let thread = try XCTUnwrap(conversation.thread)
        fixture.appState.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
        fixture.appState.selectedSidebarItem = .thread(thread)

        let provider = makeActiveConversationProvider(for: fixture.appState)

        XCTAssertEqual(provider(), conversation.id)
    }

    func testActiveConversationProviderReleasesAppStateWeakly() throws {
        let fixture = try RoutingTestFixture()
        let conversation = fixture.seedConversation(threadName: "Thread", archivedAt: nil)
        let thread = try XCTUnwrap(conversation.thread)

        var strongAppState: AppState? = AppState()
        strongAppState?.selectedConversationIDs[thread.persistentModelID] = conversation.persistentModelID
        strongAppState?.selectedSidebarItem = .thread(thread)

        let provider = makeActiveConversationProvider(for: strongAppState!)
        XCTAssertEqual(provider(), conversation.id)

        strongAppState = nil
        XCTAssertNil(provider())
    }
}

@MainActor
private struct RoutingTestFixture {
    let container: ModelContainer
    let context: ModelContext
    let appState: AppState

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        appState = AppState()
    }

    @discardableResult
    func seedConversation(threadName: String, archivedAt: Date?) -> Conversation {
        let thread = AgentThread(name: threadName, hasCustomName: true, archivedAt: archivedAt)
        let conversation = Conversation(isMain: true, thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try? context.save()
        return conversation
    }
}
