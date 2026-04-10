import Observation

@MainActor
@Observable
final class TurnState {
    private(set) var isActive = false

    func beginTurn() {
        isActive = true
    }

    func endTurn() {
        isActive = false
    }
}
