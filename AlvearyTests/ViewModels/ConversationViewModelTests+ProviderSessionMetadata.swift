import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testProviderSessionMetadataRenamesAutomaticThreadAndMainConversation() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "  Generated Codex Name  "
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Generated Codex Name")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataReplacesSyncedAutomaticThreadName() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "Fix flaky login",
            conversationTitle: "Fix flaky login"
        )

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name"
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Generated Codex Name")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataPreservesManualThreadName() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "Manual Title",
            threadHasCustomName: true
        )

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name"
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Manual Title")
        XCTAssertTrue(try fixture.dbThread().hasCustomName)
        XCTAssertNil(try fixture.dbConversation().title)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataDoesNotOverwriteDivergedMainConversationTitle() async throws {
        let fixture = try ConversationViewModelTestFixture(
            threadName: "Existing Provider Name",
            conversationTitle: "Planning"
        )

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name"
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Planning")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataIgnoresEmptyNameForVisibleRename() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "   "
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, AgentThread.untitledName)
        XCTAssertNil(try fixture.dbConversation().title)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataBypassesPromptDismissalSuppression() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)

        fixture.viewModel.beginPromptDismissResolution(promptId: "prompt-1")
        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name"
        ))
        fixture.viewModel.endPromptDismissResolution(promptId: "prompt-1")
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataCursorIsAcknowledgedAfterSave() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)
        await fixture.agentsManager.enableSubscription()

        fixture.viewModel.subscribe()
        try await waitUntil("subscription becomes active", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            await fixture.agentsManager.hasActiveSubscription()
        }

        await fixture.agentsManager.yieldSubscriptionEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name"
        ))
        try await waitUntil("metadata event observed", timeout: .seconds(1), pollInterval: .milliseconds(10)) {
            fixture.viewModel.state.lastObservedEventIndex == 1
        }
        await fixture.viewModel.flushPendingSaveIfNeeded()

        let calls = await fixture.agentsManager.markPersistedCalls()
        XCTAssertEqual(fixture.viewModel.state.lastPersistedEventIndex, 1)
        XCTAssertEqual(calls.last?.conversationId, fixture.conversation.id)
        XCTAssertEqual(calls.last?.index, 1)
        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)

        await fixture.agentsManager.finishSubscription()
    }
}
