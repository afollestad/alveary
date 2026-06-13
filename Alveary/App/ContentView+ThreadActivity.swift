extension ContentView {
    func startThreadActivityBackfillIfNeeded() {
        guard !didStartThreadActivityBackfill else {
            return
        }
        didStartThreadActivityBackfill = true
        Task { @MainActor [threadActivityRecorder] in
            await threadActivityRecorder.backfillMissingModifiedDates(batchSize: 100)
        }
    }
}
