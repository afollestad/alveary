import Testing

@testable import Alveary

@MainActor
struct ReviewStartWidgetTests {
    @Test(arguments: [false, true])
    func `started and existing reviews open their destination in both provider formats`(structured: Bool) throws {
        for existing in [false, true] {
            let message = existing
                ? "Review already exists in the thread \"Review acme/app#12\" (id: review-1)."
                : "Started the review in the thread \"Review acme/app#12\" (id: review-1)."
            let output = structured
                ? """
                {"status":"\(existing ? "existing" : "started")","thread_id":"review-1","name":"Review acme/app#12"}
                """
                : message
            let entry = try entry(output: output)

            #expect(entry.openableTarget == .thread("review-1"))
            #expect(entry.isSettledWithoutDecision)
            #expect(HostToolWidgetSummary.text(for: entry) == "\(existing ? "Review already exists" : "Review started"): Review acme/app#12")
        }
    }

    @Test func `running and refused launches have no destination`() throws {
        let running = try entry(output: nil)
        #expect(HostToolWidgetSummary.text(for: running) == "Starting review…")
        #expect(running.openableTarget == nil)

        let failed = try entry(output: #"{"status":"error","message":"The saved model is unavailable."}"#, isError: true)
        #expect(HostToolWidgetSummary.text(for: failed) == "Could not start the review")
        #expect(HostToolWidgetSummary.detail(for: failed) == "The saved model is unavailable.")
        #expect(failed.openableTarget == nil)
    }

    @Test(arguments: [false, true])
    func `a launch failure keeps its created task reachable`(structured: Bool) throws {
        let message = "Could not start the review in the thread \"Review acme/app#12\" (id: review-1). The agent could not start."
        let output = structured
            ? #"{"status":"error","thread_id":"review-1","name":"Review acme/app#12","message":"The agent could not start."}"#
            : message
        let failed = try entry(output: output, isError: true)

        #expect(failed.openableTarget == .thread("review-1"))
        #expect(HostToolWidgetSummary.detail(for: failed) == (structured ? "The agent could not start." : message))
        #expect(!failed.isSettledWithoutDecision)
    }

    @Test(arguments: [false, true])
    func `a link warning stays visible without marking the launch failed`(structured: Bool) throws {
        let output = structured
            ? #"{"status":"started","thread_id":"review-1","link_warning":"The PR could not be linked."}"#
            : "Started the review in the thread \"Review acme/app#12\" (id: review-1). Link warning: The PR could not be linked."
        let entry = try entry(output: output)

        #expect(entry.openableTarget == .thread("review-1"))
        #expect(entry.isSettledWithoutDecision)
        #expect(HostToolWidgetSummary.detail(for: entry) == "The PR could not be linked.")
    }

    @Test func `a structured receipt never invents a target from its message`() throws {
        let entry = try entry(output: #"{"status":"started","message":"Review already exists in the thread \"Ghost\" (id: ghost)."}"#)

        #expect(entry.openableTarget == nil)
        #expect(HostToolWidgetSummary.text(for: entry) == "Review started")
    }

    private func entry(output: String?, isError: Bool = false) throws -> HostToolWidgetEntry {
        let descriptor = try #require(HostToolTranscriptCatalog.descriptor(forToolName: PullRequestHostToolCatalog.startReviewToolName))
        let content = try #require(descriptor.makeContent(#"{"url":"acme/app#12"}"#, output, isError))
        return HostToolWidgetEntry(
            id: "start-review", toolName: descriptor.hostToolName, content: content,
            isComplete: output != nil, isError: isError
        )
    }
}
