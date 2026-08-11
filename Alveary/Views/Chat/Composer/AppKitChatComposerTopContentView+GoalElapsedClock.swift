import AgentCLIKit
import Foundation

final class GoalElapsedDisplayClock {
    typealias TimeProvider = () -> TimeInterval

    private let now: TimeProvider
    private var state: State?

    init(now: @escaping TimeProvider = { ProcessInfo.processInfo.systemUptime }) {
        self.now = now
    }

    func synchronize(with snapshot: AgentGoalSnapshot?) -> Int? {
        guard let snapshot else {
            state = nil
            return nil
        }

        let currentTime = now()
        switch snapshot.status {
        case .active:
            return synchronizeActive(snapshot, at: currentTime)
        case .paused, .achieved, .blocked, .usageLimited, .cleared:
            return synchronizeFrozen(snapshot, at: currentTime)
        }
    }

    func tickElapsed(for snapshot: AgentGoalSnapshot?) -> Int? {
        guard let snapshot,
              snapshot.status == .active,
              let currentState = state,
              currentState.status == .active,
              currentState.objective == snapshot.objective else {
            return synchronize(with: snapshot)
        }

        let elapsed = displayedElapsed(at: now(), state: currentState)
        state?.latestDisplayedElapsed = elapsed
        return elapsed
    }

    private func synchronizeActive(_ snapshot: AgentGoalSnapshot, at currentTime: TimeInterval) -> Int {
        let currentState = state
        // Providers do not expose a stable goal ID today, so the display clock
        // uses objective plus terminal/no-goal transitions as its UI identity.
        let startsNewGoal = currentState == nil
            || currentState?.objective != snapshot.objective
            || currentState?.status.isTerminal == true

        let elapsed: Int
        if startsNewGoal {
            elapsed = max(snapshot.elapsedSeconds ?? 0, 0)
        } else {
            let currentDisplayed = currentState.flatMap { displayedElapsed(at: currentTime, state: $0) }
            if let providerElapsed = snapshot.elapsedSeconds {
                elapsed = max(providerElapsed, currentDisplayed ?? providerElapsed, 0)
            } else {
                elapsed = max(currentDisplayed ?? 0, 0)
            }
        }

        state = State(
            objective: snapshot.objective,
            status: .active,
            baseElapsed: elapsed,
            observedAt: currentTime,
            latestDisplayedElapsed: elapsed
        )
        return elapsed
    }

    private func synchronizeFrozen(_ snapshot: AgentGoalSnapshot, at currentTime: TimeInterval) -> Int? {
        let currentState = state
        let sameGoal = currentState?.objective == snapshot.objective
        let fallbackElapsed = sameGoal ? currentState.flatMap { displayedElapsed(at: currentTime, state: $0) } : nil
        let elapsed = snapshot.elapsedSeconds ?? fallbackElapsed

        state = State(
            objective: snapshot.objective,
            status: snapshot.status,
            baseElapsed: elapsed,
            observedAt: currentTime,
            latestDisplayedElapsed: elapsed
        )
        return elapsed
    }

    private func displayedElapsed(at currentTime: TimeInterval, state: State) -> Int? {
        guard let baseElapsed = state.baseElapsed else {
            return state.latestDisplayedElapsed
        }
        guard state.status == .active else {
            return state.latestDisplayedElapsed ?? baseElapsed
        }
        let delta = max(Int(floor(currentTime - state.observedAt)), 0)
        return max(baseElapsed + delta, state.latestDisplayedElapsed ?? baseElapsed)
    }
}

private struct State {
    let objective: String
    let status: AgentGoalStatus
    let baseElapsed: Int?
    let observedAt: TimeInterval
    var latestDisplayedElapsed: Int?
}
