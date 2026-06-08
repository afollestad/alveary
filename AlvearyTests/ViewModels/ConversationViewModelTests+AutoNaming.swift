import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSendDoesNotAutoTitleMainConversationFromFirstMessage() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "Existing Thread")

        try await fixture.viewModel.send("Investigate the flaky login flow and summarize the regressions")

        XCTAssertNil(try fixture.dbConversation().title)
        XCTAssertEqual(try fixture.dbThread().name, "Existing Thread")
    }

    func testSendPreservesManualConversationTitle() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "Existing Thread", conversationTitle: "Manual Name")

        try await fixture.viewModel.send("Investigate the flaky login flow and summarize the regressions")

        XCTAssertEqual(try fixture.dbConversation().title, "Manual Name")
        XCTAssertEqual(try fixture.dbThread().name, "Existing Thread")
    }

    func testSendDoesNotAutoNameThreadFromFirstMessage() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "New thread")

        try await fixture.viewModel.send("Fix the flaky login flow")

        XCTAssertNil(try fixture.dbConversation().title)
        XCTAssertEqual(try fixture.dbThread().name, "New thread")
    }

    func testSendDoesNotAutoNameThreadWhenManualTitleMatchesDefaultLabel() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: AgentThread.untitledName,
            threadHasCustomName: true
        )

        try await fixture.viewModel.send("Fix the flaky login flow")

        XCTAssertNil(try fixture.dbConversation().title)
        XCTAssertEqual(try fixture.dbThread().name, AgentThread.untitledName)
        XCTAssertTrue(try fixture.dbThread().hasCustomName)
    }

    func testSecondaryConversationAutoTitleUsesProviderPreviewGenerator() throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "Existing Thread")
        let thread = try fixture.dbThread()
        let conversation = Conversation(
            title: nil,
            provider: "claude",
            isMain: false,
            displayOrder: 1,
            thread: thread
        )
        thread.conversations.append(conversation)
        fixture.context.insert(conversation)
        try fixture.context.save()

        _ = fixture.viewModel.insertLocalUserMessage(
            "Investigate the flaky login flow and summarize the regressions",
            into: conversation
        )

        XCTAssertEqual(conversation.title, "Investigate the flaky login flow and summarize...")
        XCTAssertEqual(thread.name, "Existing Thread")
    }

    func testConversationDisplayNameUsesStableDisplayOrderFallbacks() {
        let main = Conversation(title: nil, provider: "claude", isMain: true, displayOrder: 0)
        let second = Conversation(title: nil, provider: "claude", isMain: false, displayOrder: 1)
        let third = Conversation(title: nil, provider: "claude", isMain: false, displayOrder: 2)
        let custom = Conversation(title: "Planning", provider: "claude", isMain: false, displayOrder: 2)

        XCTAssertEqual(main.displayName(), AgentThread.untitledName)
        XCTAssertEqual(second.displayName(), "Conversation (2)")
        XCTAssertEqual(third.displayName(), "Conversation (3)")
        XCTAssertEqual(custom.displayName(), "Planning")
    }

    func testConversationDisplayNameTrimsCustomTitleAndFallsBackForBlankTitle() {
        let blank = Conversation(title: "   ", provider: "claude", isMain: false, displayOrder: 1)
        let custom = Conversation(title: "  Planning  ", provider: "claude", isMain: false, displayOrder: 1)

        XCTAssertNil(blank.customTitle)
        XCTAssertEqual(blank.displayName(), "Conversation (2)")
        XCTAssertEqual(custom.customTitle, "Planning")
        XCTAssertEqual(custom.displayName(), "Planning")
    }

    func testConversationPersistedTitleKeepsDerivedFallbackUnpersistedUntilUserOverridesIt() {
        let untitled = Conversation(title: nil, provider: "claude", isMain: false, displayOrder: 2)
        let renamed = Conversation(title: "Planning", provider: "claude", isMain: false, displayOrder: 2)

        XCTAssertNil(untitled.persistedTitle(from: "Conversation (3)"))
        XCTAssertEqual(untitled.persistedTitle(from: "  Investigate auth race  "), "Investigate auth race")
        XCTAssertEqual(renamed.persistedTitle(from: "Conversation (3)"), "Conversation (3)")
        XCTAssertNil(renamed.persistedTitle(from: "   "))
    }

    func testShouldFollowThreadRenameCascadesForUntitledAndMatchingTitlesOnly() {
        let untitledFreshConversation = Conversation(title: nil, provider: "claude", isMain: true, displayOrder: 0)
        XCTAssertTrue(
            untitledFreshConversation.shouldFollowThreadRename(previousThreadDisplayName: AgentThread.untitledName),
            "Fresh main conversation should follow its thread's first rename"
        )

        let syncedConversation = Conversation(title: "Investigate auth race", provider: "claude", isMain: true, displayOrder: 0)
        XCTAssertTrue(
            syncedConversation.shouldFollowThreadRename(previousThreadDisplayName: "Investigate auth race"),
            "A conversation whose custom title still matches the thread's previous name should stay in sync"
        )

        let divergedConversation = Conversation(title: "Planning", provider: "claude", isMain: true, displayOrder: 0)
        XCTAssertFalse(
            divergedConversation.shouldFollowThreadRename(previousThreadDisplayName: "Investigate auth race"),
            "A conversation the user has intentionally renamed should not follow the thread rename"
        )

        let legacyUntitledConversation = Conversation(title: nil, provider: "claude", isMain: true, displayOrder: 0)
        XCTAssertTrue(
            legacyUntitledConversation.shouldFollowThreadRename(previousThreadDisplayName: "Investigate auth race"),
            "A main conversation with no custom title should still follow renames, even when the thread's previous display name diverged"
        )
    }
}
