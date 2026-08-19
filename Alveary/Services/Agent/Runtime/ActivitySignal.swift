enum ActivitySignal: Sendable, Equatable {
    case neutral
    case busy
    case waitingForUser
    case idle
    case stopped
    case error
}

extension ActivitySignal {
    /// Whether the runtime has settled far enough for a queued message to go out.
    ///
    /// `.busy` and `.waitingForUser` are the only signals that mean a turn still owns the
    /// provider; every other value is a finished turn, `.error` included — a failed turn is
    /// exactly when the user's queued retry should be sent rather than parked forever. Stated
    /// here rather than at each gate so the drain and the view's re-arm cannot disagree.
    var settlesQueueDrain: Bool {
        switch self {
        case .idle, .neutral, .stopped, .error:
            return true
        case .busy, .waitingForUser:
            return false
        }
    }
}
