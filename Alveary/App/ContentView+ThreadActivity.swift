extension ContentView {
    func startThreadActivityBackfillIfNeeded() {
        guard !appState.didStartThreadActivityBackfill else {
            return
        }
        appState.didStartThreadActivityBackfill = true
        Task { @MainActor [threadActivityRecorder] in
            await threadActivityRecorder.backfillMissingModifiedDates(batchSize: 100)
        }
    }
}
