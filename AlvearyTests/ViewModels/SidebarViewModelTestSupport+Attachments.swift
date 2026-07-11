import Foundation

@testable import Alveary

actor RecordingConversationAttachmentStore: ConversationAttachmentStore {
    nonisolated private let rootDirectory = FileManager.default.temporaryDirectory
        .appendingPathComponent("sidebar-attachment-store", isDirectory: true)
    private(set) var removedConversationIDs: [String] = []

    nonisolated func conversationRootDirectory(conversationId: String) -> URL {
        rootDirectory.appendingPathComponent(conversationId, isDirectory: true)
    }

    func copyLocalImages(_ urls: [URL], conversationId: String) async throws -> [LocalImageAttachment] {
        []
    }

    func storeAppShotScreenshot(_ data: Data, conversationId: String, label: String) async throws -> LocalImageAttachment {
        throw SidebarAttachmentStoreError.unsupportedTestOperation
    }

    func cleanupUnreferenced(conversationId: String, keeping retainedURLs: Set<URL>, olderThan age: TimeInterval) async {}

    func removeAttachment(at url: URL) async throws {}

    func removeConversationDirectory(conversationId: String) async {
        removedConversationIDs.append(conversationId)
    }
}

private enum SidebarAttachmentStoreError: Error {
    case unsupportedTestOperation
}
