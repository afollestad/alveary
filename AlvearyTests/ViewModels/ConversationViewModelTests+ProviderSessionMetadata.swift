import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testProviderSessionMetadataRenamesAutomaticThreadAndMainConversation() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "  Generated Codex Name  ",
            preview: "Initial preview"
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Generated Codex Name")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataUsesPreviewWhenNameIsMissing() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: nil,
            preview: "  Initial Prompt Preview  "
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Initial Prompt Preview")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Initial Prompt Preview")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataUsesVisibleAppShotMessageForHeaderPreview() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)
        let appShot = providerMetadataAppShotAttachment()
        _ = fixture.viewModel.insertLocalUserMessage(
            "Explain the selected window state",
            into: try fixture.dbConversation(),
            appShots: [appShot]
        )

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: nil,
            preview: "# Applications mentioned by the user:..."
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Explain the selected window state")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Explain the selected window state")
    }

    func testProviderSessionMetadataUsesPersistedAppShotMessageWhenRuntimeFallbackIsMissing() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)
        let appShot = providerMetadataAppShotAttachment(isStoredInAppShotDirectory: true)
        _ = fixture.viewModel.insertLocalUserMessage(
            "Explain the selected window state",
            into: try fixture.dbConversation(),
            appShots: [appShot]
        )
        fixture.viewModel.state.appShotProviderSessionTitleFallback = nil

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: nil,
            preview: "# Applications mentioned by the user:..."
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Explain the selected window state")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Explain the selected window state")
    }

    func testProviderSessionMetadataUsesPersistedAppShotMetadataWhenScreenshotIsNotInLegacyDirectory() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)
        let appShot = providerMetadataAppShotAttachment(isStoredInAppShotDirectory: false)
        _ = fixture.viewModel.insertLocalUserMessage(
            "Explain the selected window state",
            into: try fixture.dbConversation(),
            appShots: [appShot]
        )
        fixture.viewModel.state.appShotProviderSessionTitleFallback = nil

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: nil,
            preview: "# Applications mentioned by the user:..."
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Explain the selected window state")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Explain the selected window state")
    }

    func testProviderSessionMetadataUsesAppShotFallbackForEmptyVisibleMessage() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)
        let appShot = providerMetadataAppShotAttachment()
        _ = fixture.viewModel.insertLocalUserMessage(
            "",
            into: try fixture.dbConversation(),
            appShots: [appShot]
        )

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: nil,
            preview: "# Applications mentioned by the user:..."
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "(App shot)")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "(App shot)")
    }

    func testProviderSessionMetadataExtractsClaudeAppShotRequestFromFullTransportPreview() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)
        let preview = """
        # Applications mentioned by the user:

        <appshot app="Preview" bundle-identifier="com.apple.Preview" window-title="Document" image="/tmp/appshot.png">
        Window: "Document", App: Preview.
        standard window Document, ID: main

        The focused UI element is standard window Document, ID: main
        </appshot>

        ## My request for Claude:
        ![Appshot screenshot](</tmp/appshot.png>)

        Explain the visible error state
        """

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "claude-thread",
            name: nil,
            preview: preview
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Explain the visible error state")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Explain the visible error state")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataPrefersNameOverPreview() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name",
            preview: "Initial Prompt Preview"
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Generated Codex Name")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataNameReplacesEarlierPreview() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: AgentThread.untitledName)

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: nil,
            preview: "Initial Prompt Preview"
        ))
        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name",
            preview: "Initial Prompt Preview"
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
            name: "Generated Codex Name",
            preview: "Initial preview"
        ))
        await fixture.viewModel.flushPendingSaveIfNeeded()

        XCTAssertEqual(try fixture.dbThread().name, "Generated Codex Name")
        XCTAssertFalse(try fixture.dbThread().hasCustomName)
        XCTAssertEqual(try fixture.dbConversation().title, "Generated Codex Name")
        XCTAssertTrue(try fixture.context.fetch(FetchDescriptor<ConversationEventRecord>()).isEmpty)
    }

    func testProviderSessionMetadataCascadesWhenThreadAlreadyMatchesProviderTitle() async throws {
        let fixture = try ConversationViewModelTestFixture(threadName: "Generated Codex Name")

        fixture.viewModel.handleEvent(.providerSessionMetadataChanged(
            sessionId: "codex-thread",
            name: "Generated Codex Name",
            preview: "Initial preview"
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
            name: "Generated Codex Name",
            preview: "Initial preview"
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
            name: "Generated Codex Name",
            preview: "Initial preview"
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
            name: "   ",
            preview: nil
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
            name: "Generated Codex Name",
            preview: nil
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
            name: "Generated Codex Name",
            preview: "Initial preview"
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

private func providerMetadataAppShotAttachment(isStoredInAppShotDirectory: Bool = false) -> AppShotAttachment {
    let screenshotParentDirectory = isStoredInAppShotDirectory
        ? FileManager.default.temporaryDirectory.appendingPathComponent("appshots", isDirectory: true)
        : FileManager.default.temporaryDirectory
    let screenshotURL = screenshotParentDirectory
        .appendingPathComponent("\(UUID().uuidString)-appshot.png")
    let screenshot = LocalImageAttachment(
        id: UUID().uuidString,
        fileURL: screenshotURL,
        label: "appshot.png",
        createdAt: Date()
    )
    return AppShotAttachment(
        appName: "Preview",
        bundleIdentifier: "com.apple.Preview",
        windowTitle: "Document",
        screenshot: screenshot,
        axTreeText: "standard window Document, ID: main",
        focusedElementSummary: "standard window Document, ID: main",
        attachmentStoreRoot: FileManager.default.temporaryDirectory
    )
}
