import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
final class MenuBarRecentThreadsProviderTests: XCTestCase {
    func testListsOpenableThreadsMostRecentlyModifiedFirst() throws {
        let fixture = try MenuBarRecentThreadsFixture()
        fixture.insertThread(name: "Older", conversationID: "convo-older", modifiedAt: fixture.date(-200))
        fixture.insertThread(name: "Newest", conversationID: "convo-newest", modifiedAt: fixture.date(-10))
        fixture.insertThread(name: "Middle", conversationID: "convo-middle", modifiedAt: fixture.date(-100))

        let recentThreads = fixture.provider.recentThreads()

        XCTAssertEqual(recentThreads.map(\.title), ["Newest", "Middle", "Older"])
        XCTAssertEqual(recentThreads.map(\.conversationID), ["convo-newest", "convo-middle", "convo-older"])
    }

    func testExcludesThreadsTheAppCannotOpen() throws {
        let fixture = try MenuBarRecentThreadsFixture()
        fixture.insertThread(name: "Listed", conversationID: "convo-listed", modifiedAt: fixture.date(-10))
        fixture.insertThread(
            name: "Archived",
            conversationID: "convo-archived",
            modifiedAt: fixture.date(-5),
            archivedAt: fixture.date(-1)
        )
        fixture.insertThread(name: "Draft", conversationID: "convo-draft", modifiedAt: fixture.date(-4), isDraft: true)
        fixture.insertThread(
            name: "Forking",
            conversationID: "convo-forking",
            modifiedAt: fixture.date(-3),
            isForkBootstrapPending: true
        )
        fixture.insertThread(name: "No conversation", conversationID: nil, modifiedAt: fixture.date(-2))

        XCTAssertEqual(fixture.provider.recentThreads().map(\.conversationID), ["convo-listed"])
    }

    func testHonorsTheLimit() throws {
        let fixture = try MenuBarRecentThreadsFixture()
        for index in 0..<8 {
            fixture.insertThread(
                name: "Thread \(index)",
                conversationID: "convo-\(index)",
                modifiedAt: fixture.date(Double(index))
            )
        }

        XCTAssertEqual(fixture.provider.recentThreads().count, MenuBarRecentThreadsProvider.defaultLimit)
        XCTAssertEqual(fixture.provider.recentThreads(limit: 2).map(\.conversationID), ["convo-7", "convo-6"])
        XCTAssertTrue(fixture.provider.recentThreads(limit: 0).isEmpty)
    }

    func testTruncatesLongTitlesAndCollapsesWhitespace() {
        XCTAssertEqual(MenuBarRecentThreadsProvider.menuTitle("Fix   the\nflaky test"), "Fix the flaky test")

        let long = String(repeating: "a", count: 80)
        let truncated = MenuBarRecentThreadsProvider.menuTitle(long)

        XCTAssertTrue(truncated.hasSuffix("…"))
        XCTAssertLessThan(truncated.count, long.count)
    }
}

@MainActor
private struct MenuBarRecentThreadsFixture {
    let container: ModelContainer
    let context: ModelContext
    let provider: MenuBarRecentThreadsProvider

    init() throws {
        container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        context = ModelContext(container)
        provider = MenuBarRecentThreadsProvider(modelContext: context)
    }

    func date(_ offset: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: 100_000 + offset)
    }

    func insertThread(
        name: String,
        conversationID: String?,
        modifiedAt: Date,
        archivedAt: Date? = nil,
        isDraft: Bool = false,
        isForkBootstrapPending: Bool = false
    ) {
        let thread = AgentThread(name: name, mode: .task)
        thread.modifiedAt = modifiedAt
        thread.archivedAt = archivedAt
        thread.isDraft = isDraft
        thread.isForkBootstrapPending = isForkBootstrapPending
        context.insert(thread)
        if let conversationID {
            let conversation = Conversation(id: conversationID, isMain: true)
            conversation.thread = thread
            context.insert(conversation)
        }
        try? context.save()
    }
}
