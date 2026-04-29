import Foundation

@MainActor
extension DiffWorkspaceStore {
    func setStatsLoadState(_ state: DiffWorkspaceLoadState) {
        statsLoadState = state
        if state == .loading {
            scheduleStatsLoadingIndicator()
        } else {
            hideStatsLoadingIndicator()
        }
    }

    func setSelectedDiffLoadState(_ state: DiffWorkspaceLoadState) {
        selectedDiffLoadState = state
        if state == .loading {
            scheduleSelectedDiffLoadingIndicator()
        } else {
            hideSelectedDiffLoadingIndicator()
        }
    }

    func hideSelectedDiffLoadingIndicator() {
        selectedDiffLoadingIndicatorGeneration &+= 1
        selectedDiffLoadingIndicatorTask?.cancel()
        selectedDiffLoadingIndicatorTask = nil
        isSelectedDiffLoadingIndicatorVisible = false
    }

    private func scheduleStatsLoadingIndicator() {
        guard !isStatsLoadingIndicatorVisible, statsLoadingIndicatorTask == nil else {
            return
        }

        // Give quick Git calls a grace period so toolbar/preview spinners do
        // not flash for loads that complete almost immediately.
        statsLoadingIndicatorGeneration &+= 1
        let generation = statsLoadingIndicatorGeneration
        let delay = loadingIndicatorDelay
        statsLoadingIndicatorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                  !Task.isCancelled,
                  self.statsLoadState == .loading,
                  self.statsLoadingIndicatorGeneration == generation else {
                return
            }
            self.statsLoadingIndicatorTask = nil
            self.isStatsLoadingIndicatorVisible = true
        }
    }

    private func scheduleSelectedDiffLoadingIndicator() {
        guard !isSelectedDiffLoadingIndicatorVisible, selectedDiffLoadingIndicatorTask == nil else {
            return
        }

        // The selected-file preview can finish from parser cache quickly; keep
        // the visual spinner for genuinely noticeable waits.
        selectedDiffLoadingIndicatorGeneration &+= 1
        let generation = selectedDiffLoadingIndicatorGeneration
        let delay = loadingIndicatorDelay
        selectedDiffLoadingIndicatorTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self,
                  !Task.isCancelled,
                  self.selectedDiffLoadState == .loading,
                  self.selectedDiffLoadingIndicatorGeneration == generation else {
                return
            }
            self.selectedDiffLoadingIndicatorTask = nil
            self.isSelectedDiffLoadingIndicatorVisible = true
        }
    }

    func hideStatsLoadingIndicator() {
        statsLoadingIndicatorGeneration &+= 1
        statsLoadingIndicatorTask?.cancel()
        statsLoadingIndicatorTask = nil
        isStatsLoadingIndicatorVisible = false
    }
}
