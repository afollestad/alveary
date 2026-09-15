import Foundation
import SwiftData

struct HarnessSessionBinding: Equatable, Hashable, Sendable {
    let conversationID: String
    let harnessID: String
    let harnessSessionID: String
    let workingDirectory: String?

    init(
        conversationID: String,
        harnessID: String,
        harnessSessionID: String,
        workingDirectory: String?
    ) {
        self.conversationID = conversationID
        self.harnessID = harnessID
        self.harnessSessionID = harnessSessionID
        self.workingDirectory = workingDirectory.map(CanonicalPath.normalize)
    }
}

protocol HarnessSessionBindingStore: Sendable {
    func record(_ binding: HarnessSessionBinding) async
}

struct NoopHarnessSessionBindingStore: HarnessSessionBindingStore {
    func record(_ binding: HarnessSessionBinding) async {}
}

@MainActor
final class SwiftDataHarnessSessionBindingStore: HarnessSessionBindingStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func record(_ binding: HarnessSessionBinding) async {
        let modelContext = ModelContext(modelContainer)
        guard let conversation = modelContext.resolveConversation(conversationID: binding.conversationID) else {
            return
        }

        conversation.harnessSessionId = binding.harnessSessionID
        conversation.harnessSessionHarnessId = binding.harnessID
        conversation.harnessSessionWorkingDirectory = binding.workingDirectory
        try? modelContext.save()
    }
}
