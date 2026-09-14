import Foundation
import XCTest

@testable import Alveary

@MainActor
final class AppKitTranscriptAttachmentCacheTests: XCTestCase {
    func testOneEnvelopeDecodeSuppliesImagesAppShotsAndFilesAcrossUnchangedUpdates() {
        let cache = AppKitTranscriptAttachmentCache()
        let event = message()
        let screenshot = image(id: "screenshot")
        let appShot = PersistedAppShotAttachment(
            screenshot: screenshot, appName: "Preview", bundleIdentifier: "com.apple.Preview", windowTitle: "Document", axTreeText: "AX tree"
        )
        let file = file(id: "document")
        event.setPersistedTranscriptAttachments(images: [screenshot], persistedAppShots: [appShot], files: [file])

        for _ in 0..<3 {
            let attachments = cached(cache, events: [event])
            XCTAssertEqual(attachments.imagesByMessageID[event.id], [.init(appShot: appShot)])
            XCTAssertEqual(attachments.filesByMessageID[event.id], [file])
        }

        XCTAssertEqual(cache.decodeCount, 1)
        XCTAssertEqual(cache.preparationCount, 1)
    }

    func testJSONAndRoleMutationWithUnchangedEventIDInvalidatesCopiedInputs() {
        let cache = AppKitTranscriptAttachmentCache()
        let event = message()
        let firstImage = image(id: "first-image")
        let firstFile = file(id: "first-file")
        event.setPersistedTranscriptAttachments(images: [firstImage], appShots: [], files: [firstFile])
        let initial = cached(cache, events: [event])
        let secondImage = image(id: "second-image")
        let secondFile = file(id: "second-file")
        event.setPersistedTranscriptAttachments(images: [secondImage], appShots: [], files: [secondFile])

        let changed = cached(cache, events: [event])

        XCTAssertEqual(initial.imagesByMessageID[event.id]?.map(\.image), [firstImage])
        XCTAssertEqual(changed.imagesByMessageID[event.id]?.map(\.image), [secondImage])
        XCTAssertEqual(changed.filesByMessageID[event.id], [secondFile])
        XCTAssertEqual(cache.decodeCount, 2)
        event.role = ConversationEventRecord.assistantRole
        let assistant = cached(cache, events: [event])
        XCTAssertEqual(assistant.imagesByMessageID[event.id]?.map(\.image), [secondImage])
        XCTAssertNil(assistant.filesByMessageID[event.id])
        XCTAssertEqual(cache.decodeCount, 2)
    }

    func testRuntimeMutationReusesDecodedEnvelopeAndPreservesMetadataMerge() {
        let cache = AppKitTranscriptAttachmentCache()
        let event = message()
        let screenshot = image(id: "screenshot")
        let persistedFile = file(id: "file")
        event.setPersistedTranscriptAttachments(images: [screenshot], appShots: [], files: [persistedFile])
        _ = cached(cache, events: [event])
        let runtimeFile = file(id: "file", label: "Replacement.pdf")
        let appShot = AppShotAttachment(
            appName: "Preview", bundleIdentifier: "com.apple.Preview", windowTitle: "Document", screenshot: screenshot,
            axTreeText: "Runtime AX tree", focusedElementSummary: "Window", attachmentStoreRoot: URL(fileURLWithPath: "/tmp")
        )

        let changed = cache.attachments(
            events: [event], runtimeImageAttachments: [event.id: [screenshot]],
            runtimeAppShots: [event.id: [appShot]], runtimeFileAttachments: [event.id: [runtimeFile]]
        )

        XCTAssertEqual(changed.imagesByMessageID[event.id], [.init(appShot: PersistedAppShotAttachment(appShot: appShot))])
        XCTAssertEqual(changed.filesByMessageID[event.id], [runtimeFile])
        XCTAssertEqual(cache.decodeCount, 1)
        XCTAssertEqual(cache.preparationCount, 2)
    }

    func testRemovedEventsAndMalformedPayloadsCannotLeaveStaleAttachments() {
        let cache = AppKitTranscriptAttachmentCache()
        let event = message()
        event.setPersistedPlainImageAttachments([image(id: "image")])
        _ = cached(cache, events: [event])
        XCTAssertTrue(cached(cache, events: []).imagesByMessageID.isEmpty)

        let replacement = message()
        replacement.transcriptAttachmentsJSON = "malformed"
        XCTAssertTrue(cached(cache, events: [replacement]).imagesByMessageID.isEmpty)
        XCTAssertTrue(cached(cache, events: [replacement]).imagesByMessageID.isEmpty)
        XCTAssertEqual(cache.decodeCount, 2)
        replacement.transcriptAttachmentsJSON = nil
        XCTAssertTrue(cached(cache, events: [replacement]).imagesByMessageID.isEmpty)
        XCTAssertEqual(cache.decodeCount, 2)
    }

    private func cached(_ cache: AppKitTranscriptAttachmentCache, events: [ConversationEventRecord]) -> AppKitTranscriptAttachments {
        cache.attachments(events: events, runtimeImageAttachments: [:], runtimeAppShots: [:], runtimeFileAttachments: [:])
    }

    private func message() -> ConversationEventRecord {
        ConversationEventRecord(id: "message", conversationId: "conversation", type: "message", role: "user", content: "Attachments")
    }

    private func image(id: String) -> LocalImageAttachment {
        LocalImageAttachment(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(id).png"), label: "\(id).png", createdAt: .distantPast)
    }

    private func file(id: String, label: String = "Document.pdf") -> LocalFileAttachment {
        LocalFileAttachment(id: id, fileURL: URL(fileURLWithPath: "/tmp/\(label)"), label: label, createdAt: .distantPast)
    }
}
