import Foundation
import SwiftData

struct ProviderSessionBinding: Equatable, Hashable, Sendable {
    let conversationID: String
    let providerID: String
    let providerSessionID: String
    let workingDirectory: String?

    init(
        conversationID: String,
        providerID: String,
        providerSessionID: String,
        workingDirectory: String?
    ) {
        self.conversationID = conversationID
        self.providerID = providerID
        self.providerSessionID = providerSessionID
        self.workingDirectory = workingDirectory.map(CanonicalPath.normalize)
    }
}

protocol ProviderSessionBindingStore: Sendable {
    func record(_ binding: ProviderSessionBinding) async
}

struct NoopProviderSessionBindingStore: ProviderSessionBindingStore {
    func record(_ binding: ProviderSessionBinding) async {}
}

@MainActor
final class SwiftDataProviderSessionBindingStore: ProviderSessionBindingStore {
    private let modelContainer: ModelContainer

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
    }

    func record(_ binding: ProviderSessionBinding) async {
        let modelContext = ModelContext(modelContainer)
        guard let conversation = modelContext.resolveConversation(conversationID: binding.conversationID) else {
            return
        }

        conversation.providerSessionId = binding.providerSessionID
        conversation.providerSessionProviderId = binding.providerID
        conversation.providerSessionWorkingDirectory = binding.workingDirectory
        try? modelContext.save()
    }
}
