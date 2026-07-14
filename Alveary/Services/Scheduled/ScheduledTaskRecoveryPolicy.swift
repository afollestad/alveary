import Foundation

enum ScheduledTaskRecoveryInterruptionReason: Equatable, Sendable {
    case claimedTooOld
    case claimedUnsafe
    case executionWasInProgress

    var message: String {
        switch self {
        case .claimedTooOld:
            "The claimed scheduled task was outside the recovery window."
        case .claimedUnsafe:
            "The claimed scheduled task could not be resumed safely."
        case .executionWasInProgress:
            "The scheduled task was interrupted when Alveary stopped."
        }
    }
}

enum ScheduledTaskRecoveryDecision: Equatable, Sendable {
    case ignoreTerminal
    case resumeClaimed
    case interrupt(ScheduledTaskRecoveryInterruptionReason)
}

struct ScheduledTaskRecoveryPolicy: Sendable {
    let maximumClaimAge: TimeInterval

    init(maximumClaimAge: TimeInterval = ScheduledTaskRecurrenceCalculator.defaultCatchUpAge) {
        self.maximumClaimAge = maximumClaimAge
    }

    func decision(
        status: ScheduledTaskRunStatus,
        recoveryReferenceAt: Date,
        at actionDate: Date,
        isSafeToResume: Bool
    ) -> ScheduledTaskRecoveryDecision {
        switch status {
        case .success, .failure, .interrupted, .skipped:
            return .ignoreTerminal
        case .preparing, .running, .waiting:
            return .interrupt(.executionWasInProgress)
        case .claimed:
            let age = actionDate.timeIntervalSince(recoveryReferenceAt)
            guard age >= 0, age <= maximumClaimAge else {
                return .interrupt(.claimedTooOld)
            }
            guard isSafeToResume else {
                return .interrupt(.claimedUnsafe)
            }
            return .resumeClaimed
        }
    }
}
