import Foundation

struct PendingExitPlanModeFollowUp: Equatable, Sendable {
    enum Phase: Equatable, Sendable {
        case awaitingDeniedExitTurn
        case readyToSend
    }

    let toolUseId: String
    let sessionId: String
    let harnessId: String
    let harnessSessionId: String?
    let message: String
    /// Harness-facing text for the next send; this must never be shown in transcript UI.
    let transportText: String?
    let sourceTurnId: String?
    let sourceSubscriptionToken: UUID?
    let sourceBufferGeneration: UUID?
    let sourceEventIndex: Int
    var lastObservedEventIndex: Int
    var phase: Phase
}

struct PendingExitPlanModeRevisionGuidance: Equatable, Sendable {
    let toolUseId: String
    let sessionId: String
    let harnessId: String
    let harnessSessionId: String?
}
