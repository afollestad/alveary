import Foundation

@testable import Alveary

@MainActor
final class RecordingThreadActivityRecorder: ThreadActivityRecording {
    private(set) var materializedTaskConversationIDs: [String] = []
    private(set) var visibleOutboundConversationIDs: [String] = []
    private(set) var visibleTurnEndedConversationIDs: [String] = []
    private(set) var historicalActivities: [(conversationId: String, timestamp: Date)] = []
    private(set) var backfillBatchSizes: [Int] = []

    func recordTaskMaterialized(conversationId: String) {
        materializedTaskConversationIDs.append(conversationId)
    }

    func recordVisibleOutbound(conversationId: String) {
        visibleOutboundConversationIDs.append(conversationId)
    }

    func recordVisibleTurnEnded(conversationId: String) {
        visibleTurnEndedConversationIDs.append(conversationId)
    }

    func recordHistoricalActivity(conversationId: String, timestamp: Date) {
        historicalActivities.append((conversationId, timestamp))
    }

    func backfillMissingModifiedDates(batchSize: Int) async {
        backfillBatchSizes.append(batchSize)
    }
}
