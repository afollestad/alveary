import Foundation

/// References immutable app-owned content without embedding large prompts and packets in SwiftData.
struct ReviewHistoryArtifact: Codable, Equatable, Sendable, Identifiable {
    let id: String
    let name: String
    let byteCount: Int
}

struct ReviewTeamAttempt: Codable, Equatable, Sendable, Identifiable {
    enum Status: String, Codable, Sendable {
        case running, succeeded, invalid, failed, cancelled, interrupted
    }

    static let maximumCount = 128

    let id: String
    let reviewerID: String
    let phase: ReviewTeamRun.Phase
    let generation: Int
    let startedAt: Date
    let packetHash: String
    let prompt: ReviewHistoryArtifact
    let inputs: [ReviewHistoryArtifact]
    var finishedAt: Date?
    var status: Status
    var error: String?
    var response: ReviewHistoryArtifact?
}

/// Audit capture is mandatory when configured; a missing artifact cannot count as a worker failure toward quorum.
enum ReviewTeamHistoryCaptureError: LocalizedError {
    case unavailable(String)
    case attemptLimit

    var errorDescription: String? {
        switch self {
        case .unavailable(let reason): "Could not retain review execution history. \(reason)"
        case .attemptLimit: "This review reached its execution history limit. Start a new review."
        }
    }
}

extension ReviewTeamRun {
    mutating func finishRunningAttempts(as status: ReviewTeamAttempt.Status, error: String? = nil, at date: Date = .now) {
        guard var history else { return }
        for index in history.indices where history[index].status == .running {
            history[index].status = status
            history[index].finishedAt = date
            history[index].error = error
        }
        self.history = history
    }
}
