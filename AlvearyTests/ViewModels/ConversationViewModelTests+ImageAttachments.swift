import Foundation
import XCTest

import AgentCLIKit
@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testStageLocalImageAttachmentsCopiesImagesIntoConversationStore() async throws {
        let root = temporaryDirectory()
        let sourceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let imageURL = sourceDirectory.appendingPathComponent("screen shot.png")
        let textURL = sourceDirectory.appendingPathComponent("notes.txt")
        try Self.pngHeaderData.write(to: imageURL)
        try "not an image".write(to: textURL, atomically: true, encoding: .utf8)

        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)

        try await fixture.viewModel.stageLocalImageAttachments(from: [imageURL, textURL])

        let attachment = try XCTUnwrap(fixture.viewModel.stagedImageAttachments.first)
        XCTAssertEqual(fixture.viewModel.stagedImageAttachments.count, 1)
        XCTAssertEqual(attachment.label, "screen shot.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.fileURL.path))
        XCTAssertTrue(attachment.fileURL.path.hasPrefix(root.path))
        XCTAssertTrue(attachment.fileURL.path.contains(fixture.conversation.id))
    }

    func testSupportedProviderSendUsesImageAttachmentsWithoutMarkdownFallback() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = localImageAttachment(label: "diagram.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.send("Describe this", supportsLocalImageInput: true)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, ["Describe this"])
        XCTAssertEqual(sentAttachments, [[attachment]])
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)
        let userMessages = try fixture.userMessages()
        XCTAssertEqual(userMessages.map(\.content), ["Describe this"])
        XCTAssertEqual(try XCTUnwrap(userMessages.first).persistedImageAttachments, [attachment])
        XCTAssertEqual(
            fixture.viewModel.state.transcriptImageAttachments[try XCTUnwrap(userMessages.first?.id)],
            [attachment]
        )
    }

    func testUnsupportedProviderSendConvertsStagedImagesToMarkdownText() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = localImageAttachment(label: "diagram.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.send("Describe this", supportsLocalImageInput: false)

        let fallbackText = "Describe this\n\n\(attachment.markdownImageLink)"
        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, [fallbackText])
        XCTAssertEqual(sentAttachments, [[]])
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)
        XCTAssertEqual(try fixture.userMessages().map(\.content), [fallbackText])
    }

    func testImageOnlySendCanRetryWithAttachments() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let attachment = localImageAttachment(label: "screen.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]
        await fixture.agentsManager.enqueueSendResult(.failure(.sendFailed))

        do {
            try await fixture.viewModel.send("", supportsLocalImageInput: true)
            XCTFail("Expected image-only send to fail")
        } catch let error as MockAgentsManager.MockError {
            XCTAssertEqual(error, .sendFailed)
        }

        let failedMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(failedMessage.content, "")
        XCTAssertEqual(fixture.viewModel.state.retryableFailedMessageAttachments[failedMessage.id], [attachment])

        await fixture.agentsManager.enqueueSendResult(.success(()))
        try await fixture.viewModel.retryFailedUserMessage(id: failedMessage.id)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, [""])
        XCTAssertEqual(sentAttachments, [[attachment]])
        XCTAssertFalse(fixture.viewModel.state.retryableFailedMessageIDs.contains(failedMessage.id))
        XCTAssertEqual(fixture.viewModel.state.transcriptImageAttachments[failedMessage.id], [attachment])
    }

    func testQueuedMessagePreservesImageAttachmentsUntilDrained() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.turnState.beginTurn()
        let attachment = localImageAttachment(label: "queued.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.queueOrSend("Follow-up", supportsLocalImageInput: true)

        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        XCTAssertEqual(queued.text, "Follow-up")
        XCTAssertEqual(queued.attachments, [attachment])
        XCTAssertTrue(fixture.viewModel.state.stagedImageAttachments.isEmpty)

        fixture.viewModel.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued image attachment sent") {
            await fixture.agentsManager.sentAttachments() == [[attachment]]
        }
        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, ["Follow-up"])
        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(fixture.viewModel.state.transcriptImageAttachments[userMessage.id], [attachment])
    }

    func testSteeringSendsImageAttachments() async throws {
        let fixture = try ConversationViewModelTestFixture()
        fixture.viewModel.state.turnState.beginTurn()
        let attachment = localImageAttachment(label: "steer.png")
        fixture.viewModel.state.stagedImageAttachments = [attachment]

        try await fixture.viewModel.steer("Use this", supportsLocalImageInput: true)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        let userMessages = try fixture.userMessages()
        XCTAssertEqual(sentMessages, ["Use this"])
        XCTAssertEqual(sentAttachments, [[attachment]])
        XCTAssertEqual(try XCTUnwrap(userMessages.first?.content), "Use this")
        XCTAssertEqual(
            fixture.viewModel.state.transcriptImageAttachments[try XCTUnwrap(userMessages.first?.id)],
            [attachment]
        )
        let steeringCalls = await fixture.agentsManager.steeringCalls()
        XCTAssertEqual(steeringCalls, [
            .init(
                message: "Use this",
                conversationId: fixture.conversation.id,
                steeringInputID: try XCTUnwrap(userMessages.first?.id),
                attachments: [attachment]
            )
        ])
    }

    func testTypedMarkdownImageRemainsTextOnly() async throws {
        let fixture = try ConversationViewModelTestFixture()
        let markdown = "Inspect ![Existing](existing.png)"

        try await fixture.viewModel.send(markdown, supportsLocalImageInput: true)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        XCTAssertEqual(sentMessages, [markdown])
        XCTAssertEqual(sentAttachments, [[]])
        XCTAssertEqual(try fixture.userMessages().map(\.content), [markdown])
    }

    func testCodexAppShotSendUsesHiddenTransportAndLocalImageMetadata() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "codex")
        let appShot = try localAppShotAttachment(label: "codex-appshot.png")
        fixture.viewModel.state.stagedAppShots = [appShot]

        try await fixture.viewModel.send("Describe this window", supportsLocalImageInput: true)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        let sentMetadata = await fixture.agentsManager.sentMetadata()
        let sentMessage = try XCTUnwrap(sentMessages.first)
        XCTAssertTrue(sentMessage.contains("# Applications mentioned by the user:"))
        XCTAssertTrue(sentMessage.contains("<appshot app=\"Preview\" bundle-identifier=\"com.apple.Preview\""))
        XCTAssertTrue(sentMessage.contains("image=\"\(appShot.screenshot.fileURL.path)\""))
        XCTAssertTrue(sentMessage.contains("## My request for Codex:\nDescribe this window"))
        XCTAssertEqual(sentAttachments, [[appShot.screenshot]])
        XCTAssertEqual(sentMetadata, [[CodexInputMetadata.isAppshot: .bool(true)]])
        XCTAssertTrue(fixture.viewModel.state.stagedAppShots.isEmpty)
        let userMessage = try XCTUnwrap(try fixture.userMessages().first)
        XCTAssertEqual(userMessage.content, "Describe this window")
        XCTAssertEqual(userMessage.persistedImageAttachments, [appShot.screenshot])
        XCTAssertEqual(userMessage.persistedAppShotAttachments, [PersistedAppShotAttachment(appShot: appShot)])
        XCTAssertEqual(fixture.viewModel.state.transcriptAppShots[userMessage.id], [appShot])
    }

    func testClaudeAppShotSendUsesHiddenMarkdownScreenshotAndDirectoryGrant() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")
        let storeRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let appShot = try localAppShotAttachment(label: "claude-appshot.png", attachmentStoreRoot: storeRoot)
        fixture.viewModel.state.stagedAppShots = [appShot]

        try await fixture.viewModel.send("What is visible?", supportsLocalImageInput: false)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        let sentMetadata = await fixture.agentsManager.sentMetadata()
        let sentMessage = try XCTUnwrap(sentMessages.first)
        XCTAssertTrue(sentMessage.contains("## My request for Claude:\n![Appshot screenshot](<\(appShot.screenshot.fileURL.path)>)"))
        XCTAssertTrue(sentMessage.contains("\n\nWhat is visible?"))
        XCTAssertEqual(sentAttachments, [[]])
        XCTAssertEqual(sentMetadata, [[:]])
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        let reconfigureCall = try XCTUnwrap(reconfigureCalls.first)
        XCTAssertTrue(reconfigureCall.config.allowedDirectories.contains(CanonicalPath.normalize(storeRoot.path)))
    }

    func testClaudeAppShotTransportEscapesWrapperTextAndMarkdownDestination() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")
        let storeRoot = temporaryDirectory().appendingPathComponent("clip>root", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: storeRoot.deletingLastPathComponent()) }
        let appShot = try localAppShotAttachment(
            label: "screen>shot.png",
            appName: "Preview & Co",
            bundleIdentifier: "com.example.<preview>",
            windowTitle: "A <Window> & \"Quote\"",
            axTreeText: "standard window A <Window> & content",
            focusedElementSummary: "button <Run> & Done",
            attachmentStoreRoot: storeRoot
        )
        fixture.viewModel.state.stagedAppShots = [appShot]

        try await fixture.viewModel.send("Explain <this> & that", supportsLocalImageInput: false)

        let sentMessages = await fixture.agentsManager.sentMessages()
        let sentMessage = try XCTUnwrap(sentMessages.first)
        XCTAssertTrue(sentMessage.contains("app=\"Preview &amp; Co\""))
        XCTAssertTrue(sentMessage.contains("bundle-identifier=\"com.example.&lt;preview&gt;\""))
        XCTAssertTrue(sentMessage.contains("window-title=\"A &lt;Window&gt; &amp; &quot;Quote&quot;\""))
        XCTAssertTrue(sentMessage.contains("image=\"\(appShot.screenshot.fileURL.path.replacingOccurrences(of: ">", with: "&gt;"))\""))
        XCTAssertTrue(sentMessage.contains("Window: \"A &lt;Window&gt; &amp; \"Quote\"\", App: Preview &amp; Co."))
        XCTAssertTrue(sentMessage.contains("standard window A &lt;Window&gt; &amp; content"))
        XCTAssertTrue(sentMessage.contains("The focused UI element is button &lt;Run&gt; &amp; Done"))
        XCTAssertTrue(sentMessage.contains("![Appshot screenshot](<\(appShot.screenshot.fileURL.path.replacingOccurrences(of: ">", with: "%3E"))>)"))
        XCTAssertTrue(sentMessage.contains("Explain <this> & that"))
    }

    func testQueuedClaudeAppShotKeepsHiddenTransportAndGrantsDirectoryOnDrain() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "claude")
        fixture.viewModel.activateViewLifecycle()
        fixture.viewModel.turnState.beginTurn()
        let storeRoot = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: storeRoot) }
        let appShot = try localAppShotAttachment(label: "queued-claude-appshot.png", attachmentStoreRoot: storeRoot)
        fixture.viewModel.state.stagedAppShots = [appShot]

        try await fixture.viewModel.queueOrSend("Use queued app shot", supportsLocalImageInput: false)

        let queued = try XCTUnwrap(fixture.viewModel.messageQueue.peekNext())
        XCTAssertNil(queued.requiredPlanModeEnabled)
        XCTAssertTrue(try XCTUnwrap(queued.transportText).contains("## My request for Claude:"))
        XCTAssertEqual(queued.appShots, [appShot])

        fixture.viewModel.turnState.endTurn()
        fixture.viewModel.handleTurnCompleted()

        try await waitUntil("queued Claude app shot sent") {
            await fixture.agentsManager.sentMessages().count == 1
        }
        let reconfigureCalls = await fixture.agentsManager.reconfigureCalls()
        let reconfigureCall = try XCTUnwrap(reconfigureCalls.first)
        XCTAssertTrue(reconfigureCall.config.allowedDirectories.contains(CanonicalPath.normalize(storeRoot.path)))
        let sentAttachments = await fixture.agentsManager.sentAttachments()
        let sentMetadata = await fixture.agentsManager.sentMetadata()
        XCTAssertEqual(sentAttachments, [[]])
        XCTAssertEqual(sentMetadata, [[:]])
    }

    func testUnsupportedProviderAppShotDoesNotDowngradeToMarkdown() async throws {
        let fixture = try ConversationViewModelTestFixture(providerId: "unsupported")
        let appShot = try localAppShotAttachment(label: "unsupported-appshot.png")
        fixture.viewModel.state.stagedAppShots = [appShot]

        do {
            try await fixture.viewModel.send("Use this", supportsLocalImageInput: false)
            XCTFail("Expected unsupported app-shot provider to fail")
        } catch let error as AppShotCaptureError {
            XCTAssertEqual(error, .unsupportedProvider("unsupported"))
        }

        let sentMessages = await fixture.agentsManager.sentMessages()
        XCTAssertEqual(sentMessages, [])
        XCTAssertEqual(fixture.viewModel.state.stagedAppShots, [appShot])
        XCTAssertEqual(try fixture.userMessages().count, 0)
    }

    func testCleanupRetainsStagedAppShotScreenshots() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let appShot = try localAppShotAttachment(
            label: "staged-appshot.png",
            attachmentStoreRoot: store.conversationRootDirectory(conversationId: fixture.conversation.id)
                .appendingPathComponent("appshots", isDirectory: true)
        )
        let removedImage = LocalImageAttachment(
            id: UUID().uuidString,
            fileURL: store.conversationRootDirectory(conversationId: fixture.conversation.id)
                .appendingPathComponent("removed.png"),
            label: "removed.png",
            createdAt: Date()
        )
        try FileManager.default.createDirectory(
            at: removedImage.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.pngHeaderData.write(to: removedImage.fileURL)
        fixture.viewModel.state.stagedAppShots = [appShot]
        fixture.viewModel.state.stagedImageAttachments = [removedImage]

        fixture.viewModel.removeStagedImageAttachment(id: removedImage.id)

        try await waitUntil("removed image attachment cleaned up") {
            !FileManager.default.fileExists(atPath: removedImage.fileURL.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: appShot.screenshot.fileURL.path))
    }

    func testCleanupRetainsTranscriptImageAttachments() async throws {
        let root = temporaryDirectory()
        let sourceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let sentImageURL = sourceDirectory.appendingPathComponent("sent.png")
        let removedImageURL = sourceDirectory.appendingPathComponent("removed.png")
        try Self.pngHeaderData.write(to: sentImageURL)
        try Self.pngHeaderData.write(to: removedImageURL)

        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)

        try await fixture.viewModel.stageLocalImageAttachments(from: [sentImageURL])
        let sentAttachment = try XCTUnwrap(fixture.viewModel.stagedImageAttachments.first)
        try await fixture.viewModel.send("Describe this", supportsLocalImageInput: true)

        try await fixture.viewModel.stageLocalImageAttachments(from: [removedImageURL])
        let removedAttachment = try XCTUnwrap(fixture.viewModel.stagedImageAttachments.first)
        fixture.viewModel.removeStagedImageAttachment(id: removedAttachment.id)

        try await waitUntil("removed image attachment cleaned up") {
            !FileManager.default.fileExists(atPath: removedAttachment.fileURL.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: sentAttachment.fileURL.path))
    }

    func testCleanupRetainsPersistedTranscriptImageAttachmentsAfterRuntimeStateReset() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let retainedURL = store.conversationRootDirectory(conversationId: fixture.conversation.id)
            .appendingPathComponent("persisted.png")
        let removedURL = store.conversationRootDirectory(conversationId: fixture.conversation.id)
            .appendingPathComponent("removed.png")
        try FileManager.default.createDirectory(
            at: retainedURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.pngHeaderData.write(to: retainedURL)
        try Self.pngHeaderData.write(to: removedURL)
        let retainedAttachment = LocalImageAttachment(
            id: UUID().uuidString,
            fileURL: retainedURL,
            label: "persisted.png",
            createdAt: Date()
        )
        let userMessage = ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "message",
            role: "user",
            content: "Persisted image",
            conversation: fixture.conversation
        )
        userMessage.setPersistedPlainImageAttachments([retainedAttachment])
        fixture.context.insert(userMessage)
        try fixture.context.save()

        fixture.viewModel.cleanupUnreferencedImageAttachments(olderThan: 0)

        try await waitUntil("unreferenced image attachment cleaned up") {
            !FileManager.default.fileExists(atPath: removedURL.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: retainedURL.path))
    }

    func testCleanupDoesNotDeleteOtherConversationAttachments() async throws {
        let root = temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let otherConversationID = UUID().uuidString
        let otherAttachmentURL = store.conversationRootDirectory(conversationId: otherConversationID)
            .appendingPathComponent("other.png")
        try FileManager.default.createDirectory(
            at: otherAttachmentURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.pngHeaderData.write(to: otherAttachmentURL)

        let removedAttachment = LocalImageAttachment(
            id: UUID().uuidString,
            fileURL: store.conversationRootDirectory(conversationId: fixture.conversation.id)
                .appendingPathComponent("removed.png"),
            label: "removed.png",
            createdAt: Date()
        )
        try FileManager.default.createDirectory(
            at: removedAttachment.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.pngHeaderData.write(to: removedAttachment.fileURL)
        fixture.viewModel.state.stagedImageAttachments = [removedAttachment]
        fixture.viewModel.removeStagedImageAttachment(id: removedAttachment.id)

        try await waitUntil("current conversation image cleaned up") {
            !FileManager.default.fileExists(atPath: removedAttachment.fileURL.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: otherAttachmentURL.path))
    }
}

private func localImageAttachment(label: String) -> LocalImageAttachment {
    LocalImageAttachment(
        id: UUID().uuidString,
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(label),
        label: label,
        createdAt: Date()
    )
}

private func localAppShotAttachment(
    label: String,
    appName: String = "Preview",
    bundleIdentifier: String = "com.apple.Preview",
    windowTitle: String = "A <Window>",
    axTreeText: String = "standard window A <Window>, ID: main",
    focusedElementSummary: String = "standard window A <Window>, ID: main",
    attachmentStoreRoot: URL = temporaryDirectory()
) throws -> AppShotAttachment {
    let screenshotURL = attachmentStoreRoot.appendingPathComponent(label)
    try FileManager.default.createDirectory(at: attachmentStoreRoot, withIntermediateDirectories: true)
    try Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]).write(to: screenshotURL)
    let screenshot = LocalImageAttachment(
        id: UUID().uuidString,
        fileURL: screenshotURL,
        label: label,
        createdAt: Date()
    )
    return AppShotAttachment(
        appName: appName,
        bundleIdentifier: bundleIdentifier,
        windowTitle: windowTitle,
        screenshot: screenshot,
        axTreeText: axTreeText,
        focusedElementSummary: focusedElementSummary,
        attachmentStoreRoot: attachmentStoreRoot
    )
}

private func temporaryDirectory() -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private extension ConversationViewModelTests {
    static let pngHeaderData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}
