import Foundation

extension ConversationViewModel {
    func scheduleContextWindowCacheUpdateIfNeeded(from record: ConversationEventRecord) {
        guard record.type == ConversationEventRecord.tokensType,
              let contextWindowSize = record.contextWindowSize,
              contextWindowSize > 0 else {
            return
        }

        let harnessId = capabilityHarnessID
        let selectedModel = conversation.thread?.model ?? AppSettings.defaultModelValue
        let reportedModelId = record.harnessModelId
        let cache = contextWindowCache

        Task.detached(priority: .utility) {
            await cache.update(
                harnessId: harnessId,
                selectedModel: selectedModel,
                reportedModelId: reportedModelId,
                contextWindowSize: contextWindowSize
            )
        }
    }
}
