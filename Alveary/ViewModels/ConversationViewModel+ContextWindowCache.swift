import Foundation

extension ConversationViewModel {
    func scheduleContextWindowCacheUpdateIfNeeded(from record: ConversationEventRecord) {
        guard record.type == "tokens",
              let contextWindowSize = record.contextWindowSize,
              contextWindowSize > 0 else {
            return
        }

        let providerId = conversation.provider ?? settingsService.current.defaultProvider
        let selectedModel = conversation.thread?.model ?? AppSettings.defaultModelValue
        let reportedModelId = record.providerModelId
        let cache = contextWindowCache

        Task.detached(priority: .utility) {
            await cache.update(
                providerId: providerId,
                selectedModel: selectedModel,
                reportedModelId: reportedModelId,
                contextWindowSize: contextWindowSize
            )
        }
    }
}
