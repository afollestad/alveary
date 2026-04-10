import Foundation

final class LockedState<State>: @unchecked Sendable {
    private let lock = NSLock()
    private var state: State

    init(_ initialState: State) {
        self.state = initialState
    }

    func withLock<Result>(_ body: (inout State) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
