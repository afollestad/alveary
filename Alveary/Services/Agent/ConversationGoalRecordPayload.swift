import AgentCLIKit
import Foundation

struct ConversationGoalRecordPayload: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case snapshot
        case cleared
        case terminalDismissal
    }

    let kind: Kind
    let snapshot: AgentGoalSnapshot?
    let objective: String?
    let snapshotKey: String?

    static func snapshot(_ snapshot: AgentGoalSnapshot) -> ConversationGoalRecordPayload {
        ConversationGoalRecordPayload(
            kind: .snapshot,
            snapshot: snapshot,
            objective: snapshot.objective,
            snapshotKey: snapshot.stableGoalKey
        )
    }

    static func cleared(objective: String?) -> ConversationGoalRecordPayload {
        ConversationGoalRecordPayload(
            kind: .cleared,
            snapshot: nil,
            objective: objective,
            snapshotKey: nil
        )
    }

    static func terminalDismissal(snapshot: AgentGoalSnapshot) -> ConversationGoalRecordPayload {
        ConversationGoalRecordPayload(
            kind: .terminalDismissal,
            snapshot: nil,
            objective: snapshot.objective,
            snapshotKey: snapshot.stableGoalKey
        )
    }

    var encodedString: String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }

    static func decode(from string: String?) -> ConversationGoalRecordPayload? {
        guard let string,
              let data = string.data(using: .utf8) else {
            return nil
        }
        return try? JSONDecoder().decode(ConversationGoalRecordPayload.self, from: data)
    }
}

extension AgentGoalSnapshot {
    var stableGoalKey: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self) else {
            return "\(objective)|\(status.rawValue)|\(statusReason ?? "")"
        }
        return data.base64EncodedString()
    }
}
