import Foundation
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test func `history retains exact prompts responses packet inputs and corrective attempts`() async throws {
        let setup = try historyFixture()
        let (fixture, store) = (setup.fixture, setup.store)
        defer { try? FileManager.default.removeItem(at: setup.root) }
        await fixture.worker.configure(malformedFirst: true)
        try fixture.start()
        let run = try await fixture.terminalRun()
        let history = try #require(run.history)
        #expect(run.phase == .staged)
        #expect(run.historyIsPartial != true)
        #expect(history.count == 8)
        #expect(Set(history.map(\.id)).count == history.count)
        #expect(history.allSatisfy { $0.finishedAt != nil && $0.status != .running })
        let inspections = history.filter { $0.phase == .inspecting && $0.reviewerID == "lead" }
        #expect(inspections.map(\.status) == [.invalid, .succeeded])
        let first = try #require(inspections.first)
        let retry = try #require(inspections.last)
        let originalPrompt = try await store.read(first.prompt, conversationID: run.conversationID, runID: run.id)
        let retryPrompt = try await store.read(retry.prompt, conversationID: run.conversationID, runID: run.id)
        #expect(String(data: originalPrompt, encoding: .utf8) == ReviewTeamPrompts.inspect(criteria: run.criteria))
        #expect(String(data: retryPrompt, encoding: .utf8)
            == ReviewTeamPrompts.inspect(criteria: run.criteria)
                + "\nYour previous response was invalid: Return only valid JSON matching the requested schema. Return corrected JSON only.")
        let invalidResponse = try #require(first.response)
        #expect(try await store.read(invalidResponse, conversationID: run.conversationID, runID: run.id) == Data("malformed".utf8))
        #expect(first.error == "Return only valid JSON matching the requested schema.")
        #expect(first.packetHash == retry.packetHash)
        #expect(Set(first.inputs.map(\.name)) == ["context.json", "changes.diff", "published-feedback.json", "prior-proposal.json"])
        let response = try #require(retry.response)
        let raw = try await store.read(response, conversationID: run.conversationID, runID: run.id)
        #expect(try JSONDecoder().decode(ReviewInspectionReport.self, from: raw).findings.first?.id == "untrusted")
        #expect(history.first { $0.phase == .consolidating }?.inputs.contains { $0.name == "candidates.json" } == true)
        #expect(history.first { $0.phase == .crossChecking }?.inputs.contains { $0.name == "canonical.json" } == true)
    }

    @Test func `history capture failure stops the run before any worker launches`() async throws {
        let setup = try historyFixture(maximumRunBytes: 1)
        let fixture = setup.fixture
        defer { try? FileManager.default.removeItem(at: setup.root) }
        try fixture.start()
        let run = try await fixture.terminalRun()
        #expect(run.phase == .failed)
        #expect(run.error?.contains("Could not retain review execution history") == true)
        #expect(run.history?.isEmpty == true)
        #expect(await fixture.worker.calls.isEmpty)
    }

    @Test func `cancellation closes running history and late output cannot change it`() async throws {
        let setup = try historyFixture()
        let fixture = setup.fixture
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let gate = PullRequestsServiceGate()
        defer { gate.open() }
        await fixture.worker.configure(gate: gate)
        try fixture.start()
        let pipeline = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.withPipelineCleanup(pipeline, gate: gate) {
            try await fixture.wait { await fixture.worker.inspectionCount == 3 }
            fixture.coordinator.cancel(conversationID: fixture.conversation.id)
            let cancelled = try #require(fixture.coordinator.runs[fixture.conversation.id]?.history)
            #expect(cancelled.count == 3)
            #expect(cancelled.allSatisfy { $0.status == .cancelled && $0.finishedAt != nil && $0.response == nil })
            gate.open()
            try await fixture.waitForCompletion(of: pipeline)
            #expect(await fixture.worker.completedCount == 3)
            #expect(fixture.coordinator.runs[fixture.conversation.id]?.history == cancelled)
        }
    }

    @Test func `worker failures and previous attempt history survive Retry`() async throws {
        let setup = try historyFixture()
        let fixture = setup.fixture
        defer { try? FileManager.default.removeItem(at: setup.root) }
        await fixture.worker.configure(failedInspectors: ["peer-1", "peer-2"])
        try fixture.start()
        let failed = try await fixture.terminalRun()
        let previous = try #require(failed.history)
        #expect(previous.count == 3)
        #expect(previous.filter { $0.status == .failed }.count == 2)
        #expect(previous.allSatisfy { $0.finishedAt != nil })
        await fixture.worker.configure()
        fixture.coordinator.retry(conversationID: fixture.conversation.id)
        let resumed = try await fixture.terminalRun()
        #expect(resumed.phase == .staged)
        #expect(Array(resumed.history?.prefix(previous.count) ?? []) == previous)
        #expect(resumed.history?.count == 9)
    }

    @Test func `attempt cap fails before launching another worker`() async throws {
        let setup = try historyFixture()
        let fixture = setup.fixture
        defer { try? FileManager.default.removeItem(at: setup.root) }
        var run = try fixture.makeRun()
        let artifact = ReviewHistoryArtifact(id: String(repeating: "a", count: 64), name: "prompt.txt", byteCount: 0)
        run.history = (0..<ReviewTeamAttempt.maximumCount).map { index in
            ReviewTeamAttempt(id: "old-\(index)", reviewerID: "lead", phase: .inspecting, generation: 0,
                              startedAt: .now, packetHash: "old", prompt: artifact, inputs: [], status: .succeeded)
        }
        try fixture.coordinator.persist(run)
        await #expect(throws: ReviewTeamHistoryCaptureError.self) {
            try await fixture.coordinator.perform(conversationID: run.conversationID, generation: run.generation)
        }
        #expect(await fixture.worker.calls.isEmpty)
        #expect(fixture.coordinator.runs[run.conversationID]?.history?.count == ReviewTeamAttempt.maximumCount)
    }

    @Test func `invalid history completion durably consumes its corrective retry once`() async throws {
        let setup = try historyFixture()
        let (fixture, store) = (setup.fixture, setup.store)
        defer { try? FileManager.default.removeItem(at: setup.root) }
        var run = try fixture.makeRun()
        let prompt = try await store.save(conversationID: run.conversationID, runID: run.id, name: "prompt.txt", data: Data("prompt".utf8))
        run.history = [ReviewTeamAttempt(id: "attempt", reviewerID: "lead", phase: .inspecting, generation: 0,
                                         startedAt: .now, packetHash: "packet", prompt: prompt, inputs: [], status: .running)]
        try fixture.coordinator.persist(run)
        try await fixture.coordinator.finishAttempt(run: run, executionID: "attempt", status: .invalid,
                                                     response: "malformed", error: ReviewTeamError.invalidOutput("Invalid JSON"))
        let persistedRun = try fixture.conversation.collectiveReviewRun()
        let persisted = try #require(persistedRun)
        #expect(persisted.attempts["inspecting:lead"] == 1)
        #expect(persisted.history?.first?.status == .invalid)
        #expect(persisted.history?.first?.error == "Invalid JSON")
        let response = try #require(persisted.history?.first?.response)
        #expect(try await store.read(response, conversationID: run.conversationID, runID: run.id) == Data("malformed".utf8))
        try await fixture.coordinator.finishAttempt(run: run, executionID: "attempt", status: .invalid)
        #expect(fixture.coordinator.runs[run.conversationID]?.attempts["inspecting:lead"] == 1)
    }

    @Test func `recovery closes old running attempts and retains history across input invalidation`() async throws {
        let setup = try historyFixture()
        let (fixture, store) = (setup.fixture, setup.store)
        defer { try? FileManager.default.removeItem(at: setup.root) }
        await fixture.worker.configure(empty: true)
        var run = try fixture.makeRun()
        let artifact = try await store.save(conversationID: run.conversationID, runID: run.id, name: "prompt.txt", data: Data("old".utf8))
        run.history = [ReviewTeamAttempt(id: "old", reviewerID: "lead", phase: .inspecting, generation: 0,
                                         startedAt: .now, packetHash: "old", prompt: artifact, inputs: [], status: .running)]
        run.phase = .interrupted
        run.inputHash = "old"
        try fixture.coordinator.persist(run)
        fixture.coordinator.recover()
        let resumed = try await fixture.terminalRun()
        #expect(resumed.history?.first?.status == .interrupted)
        #expect(resumed.history?.first?.finishedAt != nil)
        #expect(resumed.history?.count == 4)
        #expect(try await store.read(artifact, conversationID: run.conversationID, runID: run.id) == Data("old".utf8))
    }

    @Test func `legacy runs decode without history and later captures remain explicitly partial`() async throws {
        let setup = try historyFixture()
        let fixture = setup.fixture
        defer { try? FileManager.default.removeItem(at: setup.root) }
        await fixture.worker.configure(empty: true)
        let run = try fixture.makeRun()
        try fixture.coordinator.persist(run)
        let legacyJSON = try #require(fixture.conversation.pullRequestReviewRunJSON)
        #expect(!legacyJSON.contains("\"history\""))
        #expect(!legacyJSON.contains("\"historyIsPartial\""))
        let decodedRun = try fixture.conversation.collectiveReviewRun()
        let decoded = try #require(decodedRun)
        #expect(decoded.history == nil)
        #expect(decoded.historyIsPartial == nil)
        try await fixture.coordinator.perform(conversationID: run.conversationID, generation: run.generation)
        let completedRun = try fixture.conversation.collectiveReviewRun()
        let completed = try #require(completedRun)
        #expect(completed.history?.count == 3)
        #expect(completed.historyIsPartial == true)
    }

    @Test func `deleted tasks discard history and late worker output cannot recreate it`() async throws {
        let setup = try historyFixture()
        let (fixture, store) = (setup.fixture, setup.store)
        defer { try? FileManager.default.removeItem(at: setup.root) }
        let gate = PullRequestsServiceGate()
        defer { gate.open() }
        await fixture.worker.configure(gate: gate)
        try fixture.start()
        let pipeline = try #require(fixture.coordinator.scheduledTaskForTesting(conversationID: fixture.conversation.id))
        try await fixture.withPipelineCleanup(pipeline, gate: gate) {
            try await fixture.wait { await fixture.worker.inspectionCount == 3 }
            let conversationID = fixture.conversation.id
            let run = try #require(fixture.coordinator.runs[conversationID])
            let artifact = try #require(run.history?.first?.prompt)
            fixture.container.mainContext.delete(fixture.conversation)
            try fixture.container.mainContext.save()
            fixture.coordinator.conversationDidDelete(conversationID)
            try await fixture.wait {
                (try? await store.read(artifact, conversationID: conversationID, runID: run.id)) == nil
            }
            gate.open()
            try await fixture.waitForCompletion(of: pipeline)
            #expect(await fixture.worker.completedCount == 3)
            #expect(fixture.coordinator.runs[conversationID] == nil)
            #expect(try !fixture.coordinator.cancellationStore.contains(runID: run.id))
            await #expect(throws: ReviewTeamHistoryStoreError.self) {
                try await store.save(conversationID: conversationID, runID: run.id, name: "late.txt", data: Data("late".utf8))
            }
        }
    }

    private func historyFixture(maximumRunBytes: Int = 128 * 1024 * 1024) throws -> ReviewHistoryTestSetup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-history-tests-\(UUID().uuidString)")
        let store = ReviewTeamHistoryStore(rootDirectory: root, maximumRunBytes: maximumRunBytes)
        return try ReviewHistoryTestSetup(fixture: ReviewCoordinatorFixture(historyStore: store), store: store, root: root)
    }
}

private struct ReviewHistoryTestSetup {
    let fixture: ReviewCoordinatorFixture
    let store: ReviewTeamHistoryStore
    let root: URL
}
