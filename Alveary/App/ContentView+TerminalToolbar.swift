import SwiftData
import SwiftUI

/// Shared toolbar state: the selected thread the toolbar acts on, plus the
/// terminal button's title and running/completed display state. Split out of
/// `ContentView.swift` to keep that file under the length limit.
extension ContentView {
    /// The selected thread, or nil for a draft or any non-thread selection.
    /// Every toolbar affordance scoped to a thread gates on this.
    var selectedThreadID: PersistentIdentifier? {
        guard case .thread(let thread) = appState.selectedSidebarItem,
              !thread.isDraft else {
            return nil
        }

        return thread.persistentModelID
    }

    var terminalToggleTitle: String {
        appState.isTerminalPaneVisible ? "Hide Terminal" : "Show Terminal"
    }

    func toggleTerminalPane() {
        if appState.isTerminalPaneVisible {
            appState.hideTerminalPane()
        } else {
            ensureDefaultShellSession(focus: true)
            appState.showTerminalPane()
        }
    }

    func handleTerminalRunningSessionIDsChange(_ runningSessionIDs: Set<UUID>) {
        let liveSessionIDs = Set(terminalManager.sessions.map(\.id))
        terminalToolbarTrackedSessionIDs.formIntersection(liveSessionIDs)

        if !runningSessionIDs.isEmpty {
            terminalToolbarResetTask?.cancel()
            terminalToolbarResetTask = nil
            terminalToolbarTrackedSessionIDs.formUnion(runningSessionIDs)
            terminalToolbarDisplayState = .running
            return
        }

        guard !terminalToolbarTrackedSessionIDs.isEmpty else {
            terminalToolbarDisplayState = .idle
            return
        }

        let completedSessionIDs = terminalToolbarTrackedSessionIDs
        terminalToolbarTrackedSessionIDs = []

        guard let outcome = TerminalToolbarCompletionOutcome.outcome(
            completedSessionIDs: completedSessionIDs,
            terminalManager: terminalManager
        ) else {
            terminalToolbarDisplayState = .idle
            return
        }

        terminalToolbarDisplayState = .completed(outcome)
        scheduleTerminalToolbarReset()
    }

    func scheduleTerminalToolbarReset() {
        terminalToolbarResetTask?.cancel()
        terminalToolbarResetTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else {
                return
            }
            terminalToolbarDisplayState = .idle
            terminalToolbarResetTask = nil
        }
    }
}
