import Foundation
import Testing

@testable import Alveary

@MainActor
struct CollectiveReviewTranscriptTests {
    @Test(arguments: [ReviewTeamRun.Phase.staged, .failed, .interrupted, .cancelled])
    func `incremental refresh replaces a run changed while its task was hidden`(phase: ReviewTeamRun.Phase) throws {
        let fixture = try ReviewCoordinatorFixture()
        var run = try fixture.makeRun()
        run.phase = .crossChecking
        try fixture.coordinator.persist(run)
        let event = try #require(fixture.conversation.events.first { $0.type == ConversationEventRecord.collectiveReviewRunType })
        let message = ConversationEventRecord(
            id: "user-message", conversationId: run.conversationID,
            type: ConversationEventRecord.messageType, role: ConversationEventRecord.userRole, content: "Review this PR."
        )
        let grouper = ChatItemGrouper()
        grouper.update(events: [message, event])
        let priorMessage = grouper.items.first
        let initial = try #require(grouper.items.last?.hostToolWidgetEntry)
        #expect(!initial.isComplete)
        run.phase = phase
        try fixture.coordinator.persist(run)

        grouper.update(events: [message, event])

        let updated = try #require(grouper.items.last?.hostToolWidgetEntry)
        let persisted = try #require(try fixture.conversation.collectiveReviewRun())
        #expect(updated.content == .collectiveReviewRun(persisted))
        #expect(updated.isComplete)
        #expect(updated.isError == (phase == .failed))
        #expect(updated.isInterrupted == (phase == .interrupted || phase == .cancelled))
        #expect(grouper.items.count == 2)
        #expect(grouper.items.first == priorMessage)
        #expect(grouper.processedCount == 2)
        let items = grouper.items
        grouper.update(events: [message, event])
        #expect(grouper.items == items)
        #expect(grouper.collectiveReviewRunContentsByEventID == [event.id: event.content!])
        grouper.resetAllState()
        #expect(grouper.collectiveReviewRunContentsByEventID.isEmpty)
    }
}
