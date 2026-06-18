import AgentCLIKit
import Foundation

extension AgentCLIKitEventMapper {
    func taskListSnapshotEvent(from envelope: AgentCLIKit.AgentEventEnvelope) -> ConversationEvent? {
        var reducer = AgentTaskListReducer()
        guard let snapshot = reducer.append(envelope) else {
            return nil
        }
        return .taskListSnapshot(ConversationTaskListSnapshot(snapshot))
    }

    func isNonDurablePlanDelta(_ event: AgentCLIKit.AgentTaskEvent) -> Bool {
        event.metadata["codex_plan_delta"] != nil
    }
}

private extension ConversationTaskListSnapshot {
    init(_ snapshot: AgentTaskListSnapshot) {
        self.init(
            id: snapshot.id,
            items: snapshot.items.map(ConversationTaskListItem.init)
        )
    }
}

private extension ConversationTaskListItem {
    init(_ item: AgentTaskListItem) {
        self.init(
            id: item.id,
            content: item.subject,
            activeForm: item.activeForm,
            status: ConversationTaskListStatus(item.status)
        )
    }
}

private extension ConversationTaskListStatus {
    init(_ status: AgentTaskListItem.Status) {
        switch status {
        case .pending:
            self = .pending
        case .inProgress:
            self = .inProgress
        case .completed:
            self = .completed
        }
    }
}
