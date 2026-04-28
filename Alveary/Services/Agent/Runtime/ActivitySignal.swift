enum ActivitySignal: Sendable, Equatable {
    case neutral
    case busy
    case waitingForUser
    case idle
    case stopped
    case error
}
