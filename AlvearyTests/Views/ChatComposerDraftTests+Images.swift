import XCTest

@testable import Alveary

@MainActor
extension ChatComposerDraftTests {
    func testLocalImageSelectionStagesImagesWhenProviderSupportsAttachments() async throws {
        let root = temporaryDirectory()
        let sourceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let imageURL = sourceDirectory.appendingPathComponent("picked.png")
        try Self.pngHeaderData.write(to: imageURL)

        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let chatView = makeChatView(fixture: fixture, appState: AppState(), supportsLocalImageInput: true)

        let result = await chatView.handleLocalFileURLsSelected([imageURL])

        XCTAssertEqual(result, .handled)
        let attachment = try XCTUnwrap(fixture.viewModel.stagedImageAttachments.first)
        XCTAssertEqual(attachment.label, "picked.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: attachment.fileURL.path))
    }

    func testStagedImagePreviewOpenPresentsInAppPreview() async throws {
        let root = temporaryDirectory()
        let sourceDirectory = temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: sourceDirectory)
        }
        let imageURL = sourceDirectory.appendingPathComponent("picked.png")
        try Self.pngHeaderData.write(to: imageURL)

        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let appState = AppState()
        let chatView = makeChatView(fixture: fixture, appState: appState, supportsLocalImageInput: true)

        _ = await chatView.handleLocalFileURLsSelected([imageURL])
        let preview = try XCTUnwrap(chatView.stagedImagePreviewAttachments.first)
        preview.open(preview)

        let request = try XCTUnwrap(appState.imagePreviewRequest)
        XCTAssertEqual(request.title, "picked.png")
        if case .fileURL(let openedURL) = request.source {
            XCTAssertEqual(openedURL, preview.fileURL.standardizedFileURL)
        } else {
            XCTFail("Expected a file URL image preview request.")
        }
    }

    func testLocalImageSelectionUsesMarkdownPathWhenProviderDoesNotSupportAttachments() async throws {
        let imageURL = FileManager.default.temporaryDirectory.appendingPathComponent("picked.png")
        let fixture = try ConversationViewModelTestFixture()
        let chatView = makeChatView(fixture: fixture, appState: AppState(), supportsLocalImageInput: false)

        let result = await chatView.handleLocalFileURLsSelected([imageURL])

        XCTAssertEqual(result, .useDefault)
        XCTAssertTrue(fixture.viewModel.stagedImageAttachments.isEmpty)
    }
}
