import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testAutomaticAttachmentCleanupReusesTranscriptAndSurvivesControllerReplacement() async throws {
        let store = RecordingAttachmentMaintenanceStore()
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let initialRequests = await store.requests
        XCTAssertTrue(initialRequests.isEmpty)
        let persisted = maintenanceAttachment("persisted")
        let staged = maintenanceAttachment("staged")
        let queued = maintenanceAttachment("queued")
        let retryable = maintenanceAttachment("retryable")
        let transcript = maintenanceAttachment("transcript")
        let record = ConversationEventRecord(
            conversationId: fixture.conversation.id, type: "message", role: "user", content: "Image", conversation: fixture.conversation
        )
        record.setPersistedPlainImageAttachments([persisted])
        fixture.context.insert(record)
        fixture.viewModel.state.stagedImageAttachments = [staged]
        fixture.viewModel.state.messageQueue.enqueue("Queued image", attachments: [queued])
        fixture.viewModel.state.retryableFailedMessageAttachments["failed"] = [retryable]
        fixture.viewModel.state.transcriptImageAttachments["visible"] = [transcript]

        // The shared main-context fetch includes an unsaved record; no detached database snapshot may omit it.
        fixture.viewModel.rebuildChatItemsFromConversationRecords()
        try await waitUntil("automatic attachment maintenance scheduled") { await store.requests.count == 1 }
        let firstRequest = await store.requests.first
        let request = try XCTUnwrap(firstRequest)
        XCTAssertEqual(request.conversationID, fixture.conversation.id)
        XCTAssertEqual(request.retainedURLs, Set([persisted, staged, queued, retryable, transcript].map(\.fileURL)))
        XCTAssertEqual(request.age, 60 * 60 * 24 * 30)

        let replacement = ConversationViewModel(
            conversation: fixture.conversation,
            agentsManager: fixture.agentsManager,
            runtimeStore: fixture.runtimeStore,
            keepAwakeService: fixture.keepAwakeService,
            modelContext: fixture.context,
            settingsService: fixture.settingsService,
            worktreeManager: fixture.worktreeManager,
            providerSetup: fixture.providerSetup,
            contextWindowCache: fixture.contextWindowCache,
            attachmentStore: store
        )
        replacement.rebuildChatItemsFromConversationRecords()
        replacement.rebuildChatItemsFromConversationRecords()
        let requests = await store.requests
        XCTAssertEqual(requests.count, 1)

        replacement.cleanupUnreferencedImageAttachments(olderThan: 0)
        try await waitUntil("explicit removal still cleans immediately") { await store.requests.count == 2 }
        let explicitRequest = await store.requests.last
        XCTAssertEqual(explicitRequest?.age, 0)
        XCTAssertEqual(explicitRequest?.retainedURLs, request.retainedURLs)
    }

    func testFallbackTranscriptDoesNotAuthorizeAutomaticAttachmentCleanup() async throws {
        let store = RecordingAttachmentMaintenanceStore()
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let record = ConversationEventRecord(
            conversationId: fixture.conversation.id, type: "message", role: "assistant", content: "Fallback"
        )
        let records = try XCTUnwrap(ConversationTranscriptRecordRefresh.resolve(
            fallbackEvents: [record], currentProcessedCount: 0, fetch: { throw FixtureError.missingConversation }
        ))

        fixture.viewModel.rebuildChatItemsIfNeeded(from: records)
        let requests = await store.requests
        XCTAssertTrue(requests.isEmpty)
        XCTAssertFalse(fixture.viewModel.state.hasScheduledAutomaticAttachmentCleanup)

        fixture.viewModel.rebuildChatItemsFromConversationRecords()
        try await waitUntil("a successful empty fetch can authorize maintenance") { await store.requests.count == 1 }
    }

    private func maintenanceAttachment(_ name: String) -> LocalImageAttachment {
        LocalImageAttachment(id: name, fileURL: URL(fileURLWithPath: "/tmp/\(name).png"), label: name, createdAt: Date())
    }
}

private actor RecordingAttachmentMaintenanceStore: ConversationAttachmentStore {
    struct Request: Sendable {
        let conversationID: String
        let retainedURLs: Set<URL>
        let age: TimeInterval
    }

    var requests: [Request] = []

    nonisolated func conversationRootDirectory(conversationId: String) -> URL {
        URL(fileURLWithPath: "/tmp/attachment-maintenance/\(conversationId)")
    }

    func cleanupUnreferenced(conversationId: String, keeping retainedURLs: Set<URL>, olderThan age: TimeInterval) async {
        requests.append(Request(conversationID: conversationId, retainedURLs: retainedURLs, age: age))
    }

    func copyLocalImages(_ urls: [URL], conversationId: String) async throws -> [LocalImageAttachment] { [] }
    func storeAppShotScreenshot(_ data: Data, conversationId: String, label: String) async throws -> LocalImageAttachment {
        throw FixtureError.missingConversation
    }
    func removeAttachment(at url: URL) async throws {}
    func removeConversationDirectory(conversationId: String) async {}
}
