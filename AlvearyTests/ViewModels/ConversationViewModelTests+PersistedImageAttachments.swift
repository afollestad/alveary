import Foundation
import XCTest

@testable import Alveary

@MainActor
extension ConversationViewModelTests {
    func testPersistedTranscriptAttachmentsDecodeLegacyImageArray() throws {
        let attachment = persistedTestImageAttachment(label: "legacy.png")
        let record = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Legacy")
        let data = try JSONEncoder().encode([attachment])
        record.transcriptAttachmentsJSON = String(data: data, encoding: .utf8)

        XCTAssertEqual(record.persistedPlainImageAttachments, [attachment])
        XCTAssertEqual(record.persistedAppShotAttachments, [])
        XCTAssertEqual(record.persistedImageAttachments, [attachment])
        XCTAssertEqual(record.persistedFileAttachments, [])
    }

    func testPersistedTranscriptAttachmentsRoundTripImageAppShotAndFileMetadata() throws {
        let image = persistedTestImageAttachment(label: "plain.png")
        let file = persistedTestFileAttachment(label: "report.pdf")
        let appShot = try persistedTestAppShotAttachment(label: "persisted-appshot.png")
        let record = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Describe")

        record.setPersistedTranscriptAttachments(images: [image, appShot.screenshot], appShots: [appShot], files: [file])

        XCTAssertEqual(record.persistedPlainImageAttachments, [image, appShot.screenshot])
        XCTAssertEqual(record.persistedAppShotAttachments, [PersistedAppShotAttachment(appShot: appShot)])
        XCTAssertEqual(record.persistedImageAttachments, [image, appShot.screenshot])
        XCTAssertEqual(record.persistedFileAttachments, [file])
        XCTAssertTrue(try XCTUnwrap(record.transcriptAttachmentsJSON).contains(appShot.axTreeText))
        XCTAssertTrue(try XCTUnwrap(record.transcriptAttachmentsJSON).contains(file.label))
        XCTAssertFalse(try XCTUnwrap(record.transcriptAttachmentsJSON).contains(appShot.focusedElementSummary))
        XCTAssertFalse(try XCTUnwrap(record.transcriptAttachmentsJSON).contains("attachmentStoreRoot"))
    }

    func testPersistedTranscriptAttachmentsDecodeLegacyAppShotMetadataWithoutAXTreeText() {
        let record = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Legacy")
        record.transcriptAttachmentsJSON = """
        {
          "version": 1,
          "images": [],
          "appShots": [
            {
              "screenshot": {
                "id": "legacy-appshot",
                "fileURL": "file:///tmp/legacy-appshot.png",
                "label": "legacy-appshot.png",
                "createdAt": 0
              },
              "appName": "Preview",
              "bundleIdentifier": "com.apple.Preview",
              "windowTitle": "Preview - Document.pdf"
            }
          ]
        }
        """

        XCTAssertEqual(record.persistedAppShotAttachments.count, 1)
        XCTAssertNil(record.persistedAppShotAttachments.first?.axTreeText)
        XCTAssertEqual(record.persistedFileAttachments, [])
    }

    func testEmptyPersistedTranscriptAttachmentsClearJSON() {
        let record = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Empty")
        record.setPersistedPlainImageAttachments([persistedTestImageAttachment(label: "plain.png")])

        record.setPersistedTranscriptAttachments(images: [], appShots: [], files: [])

        XCTAssertNil(record.transcriptAttachmentsJSON)
        XCTAssertEqual(record.persistedImageAttachments, [])
        XCTAssertEqual(record.persistedAppShotAttachments, [])
        XCTAssertEqual(record.persistedFileAttachments, [])
    }

    func testCorruptPersistedTranscriptAttachmentsDecodeAsEmpty() {
        let record = ConversationEventRecord(conversationId: "conversation", type: "message", role: "user", content: "Corrupt")
        record.transcriptAttachmentsJSON = "{not-json"

        XCTAssertEqual(record.persistedImageAttachments, [])
        XCTAssertEqual(record.persistedAppShotAttachments, [])
        XCTAssertEqual(record.persistedFileAttachments, [])
    }

    func testCleanupRetainsPersistedAppShotScreenshotAfterRuntimeStateReset() async throws {
        let root = persistedTestTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = DefaultConversationAttachmentStore(rootDirectory: root)
        let fixture = try ConversationViewModelTestFixture(attachmentStore: store)
        let appShotRoot = store.conversationRootDirectory(conversationId: fixture.conversation.id)
            .appendingPathComponent("appshots", isDirectory: true)
        let appShot = try persistedTestAppShotAttachment(label: "persisted-appshot.png", attachmentStoreRoot: appShotRoot)
        let removedURL = store.conversationRootDirectory(conversationId: fixture.conversation.id)
            .appendingPathComponent("removed.png")
        try persistedTestPNGHeaderData.write(to: removedURL)
        let userMessage = ConversationEventRecord(
            conversationId: fixture.conversation.id,
            type: "message",
            role: "user",
            content: "Persisted app shot",
            conversation: fixture.conversation
        )
        userMessage.setPersistedTranscriptAttachments(images: [], appShots: [appShot])
        fixture.context.insert(userMessage)
        try fixture.context.save()

        fixture.viewModel.cleanupUnreferencedImageAttachments(olderThan: 0)

        try await waitUntil("unreferenced image attachment cleaned up") {
            !FileManager.default.fileExists(atPath: removedURL.path)
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: appShot.screenshot.fileURL.path))
    }
}

private func persistedTestImageAttachment(label: String) -> LocalImageAttachment {
    LocalImageAttachment(
        id: UUID().uuidString,
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(label),
        label: label,
        createdAt: Date()
    )
}

private func persistedTestFileAttachment(label: String) -> LocalFileAttachment {
    LocalFileAttachment(
        id: UUID().uuidString,
        fileURL: FileManager.default.temporaryDirectory.appendingPathComponent(label),
        label: label,
        createdAt: Date()
    )
}

private func persistedTestAppShotAttachment(
    label: String,
    attachmentStoreRoot: URL = persistedTestTemporaryDirectory()
) throws -> AppShotAttachment {
    let screenshotURL = attachmentStoreRoot.appendingPathComponent(label)
    try FileManager.default.createDirectory(at: attachmentStoreRoot, withIntermediateDirectories: true)
    try persistedTestPNGHeaderData.write(to: screenshotURL)
    let screenshot = LocalImageAttachment(
        id: UUID().uuidString,
        fileURL: screenshotURL,
        label: label,
        createdAt: Date()
    )
    return AppShotAttachment(
        appName: "Preview",
        bundleIdentifier: "com.apple.Preview",
        windowTitle: "A <Window>",
        screenshot: screenshot,
        axTreeText: "standard window A <Window>, ID: main",
        focusedElementSummary: "focused button Done, ID: done",
        attachmentStoreRoot: attachmentStoreRoot
    )
}

private let persistedTestPNGHeaderData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])

private func persistedTestTemporaryDirectory() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("AlvearyTests-\(UUID().uuidString)", isDirectory: true)
}
