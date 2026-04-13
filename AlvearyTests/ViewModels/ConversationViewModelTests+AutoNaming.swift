import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testSendAutoNamesConversationFromFirstMessageWhenEnabled() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "Existing Thread")

        try await fixture.viewModel.send("Investigate the flaky login flow and summarize the regressions")

        XCTAssertEqual(try fixture.dbConversation().title, "Investigate the flaky login flow and summarize...")
        XCTAssertEqual(try fixture.dbThread().name, "Existing Thread")
    }

    func testSendDoesNotAutoNameConversationWhenSettingDisabled() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "Existing Thread")
        fixture.settingsService.update { $0.autoGenerateNames = false }

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

    func testSendAutoNamesThreadFromFirstMessageWhenEnabled() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "New thread")

        try await fixture.viewModel.send("Fix the flaky login flow")

        XCTAssertEqual(try fixture.dbConversation().title, "Fix the flaky login flow")
        XCTAssertEqual(try fixture.dbThread().name, "Fix the flaky login flow")
    }

    func testSendDoesNotAutoNameThreadWhenSettingDisabled() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "New thread")
        fixture.settingsService.update { $0.autoGenerateNames = false }

        try await fixture.viewModel.send("Fix the flaky login flow")

        XCTAssertNil(try fixture.dbConversation().title)
        XCTAssertEqual(try fixture.dbThread().name, "New thread")
    }

    func testConversationDisplayNameUsesStableDisplayOrderFallbacks() {
        let main = Conversation(title: nil, provider: "claude", isMain: true, displayOrder: 0)
        let second = Conversation(title: nil, provider: "claude", isMain: false, displayOrder: 1)
        let third = Conversation(title: nil, provider: "claude", isMain: false, displayOrder: 2)
        let custom = Conversation(title: "Planning", provider: "claude", isMain: false, displayOrder: 2)

        XCTAssertEqual(main.displayName(), "Main")
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
}
