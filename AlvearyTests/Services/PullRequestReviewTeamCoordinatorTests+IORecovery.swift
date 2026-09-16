import Foundation
import Testing

@testable import Alveary

@MainActor
extension PullRequestReviewTeamCoordinatorTests {
    @Test func `recovered Codex output passes consensus and retains the final response in history`() async throws {
        let response = "```json\n" + ioRecoveryInspection + "\n```"
        let setup = try ioRecoveryFixture(finalResponses: [response])
        defer { try? FileManager.default.removeItem(at: setup.root) }
        try setup.fixture.start(team: ioRecoveryTeam)

        let run = try await setup.fixture.terminalRun()
        #expect(run.phase == .staged)
        #expect(run.attempts.isEmpty)
        #expect(run.accepted.count == 1)
        let findings = try #require(run.inspections["lead"]?.findings)
        #expect(findings.count == 1)
        #expect(findings.first?.id != "untrusted")
        #expect(findings.first?.evidence == "Concrete support.")
        let history = try #require(run.history)
        let inspection = try #require(history.first { $0.reviewerID == "lead" && $0.phase == .inspecting })
        #expect(inspection.status == .succeeded)
        #expect(inspection.error == nil)
        let artifact = try #require(inspection.response)
        #expect(try await setup.store.read(artifact, conversationID: run.conversationID, runID: run.id) == Data(response.utf8))
        #expect(await setup.execution.callCount == 1)
        #expect(try setup.fixture.conversation.pullRequestReviewProposal() != nil)
    }

    @Test func `recovered Codex output still gets schema validation and a corrective retry`() async throws {
        let invalid = """
        {"findings":[{"id":"untrusted","priority":2,"path":"File0.swift","line":1,"side":"RIGHT","body":"A concrete problem."}]}
        """
        let responses = [invalid, ioRecoveryInspection]
        let setup = try ioRecoveryFixture(finalResponses: responses)
        defer { try? FileManager.default.removeItem(at: setup.root) }
        try setup.fixture.start(team: ioRecoveryTeam)

        let run = try await setup.fixture.terminalRun()
        #expect(run.phase == .staged)
        #expect(run.attempts["inspecting:lead"] == 1)
        let history = try #require(run.history)
        let inspections = history.filter { $0.reviewerID == "lead" && $0.phase == .inspecting }
        #expect(inspections.map(\.status) == [.invalid, .succeeded])
        let diagnostic = "Missing required field at $.findings[0].evidence."
        #expect(inspections.first?.error == diagnostic)
        for (attempt, response) in zip(inspections, responses) {
            let artifact = try #require(attempt.response)
            #expect(try await setup.store.read(artifact, conversationID: run.conversationID, runID: run.id) == Data(response.utf8))
        }
        let prompts = await setup.execution.prompts
        #expect(prompts.count == 2)
        #expect(prompts.last == ReviewTeamPrompts.inspect(criteria: run.criteria)
            + "\nYour previous response was invalid: \(diagnostic) Return corrected JSON only.")
        let calls = await setup.fixture.worker.calls
        #expect(calls.filter { $0.phase == "inspection" }.count == 2)
        #expect(run.accepted.count == 1)
    }

    @Test func `codex IO rejection persists context without capturing unverified response content`() async throws {
        let stream = """
        {"type":"turn.started"}
        {"type":"item.completed","item":{"type":"agent_message","text":"private-response-marker"}}
        not-json-private-marker

        """
        let setup = try ioRecoveryFixture(outcomes: [.ioFailure(stream)])
        defer { try? FileManager.default.removeItem(at: setup.root) }
        try setup.fixture.start(team: ioRecoveryTeam)

        _ = try await setup.fixture.terminalRun()
        let saved = try setup.fixture.conversation.collectiveReviewRun()
        let persisted = try #require(saved)
        let attempt = try #require(persisted.history?.first { $0.reviewerID == "lead" && $0.phase == .inspecting })
        #expect(attempt.status == .failed)
        #expect(attempt.response == nil)
        let diagnostic = try #require(attempt.error)
        #expect(diagnostic.contains("Review execution failed"))
        #expect(diagnostic.contains("invalid JSON event or missing event type at record 3"))
        #expect(diagnostic.contains("captured stdout: \(stream.utf8.count) bytes"))
        #expect(diagnostic.contains("exited with code 0"))
        #expect(persisted.failures["inspecting:lead"] == diagnostic)
        let envelope = try #require(setup.fixture.conversation.pullRequestReviewRunJSON)
        #expect(!envelope.contains("private-response-marker"))
        #expect(!envelope.contains("not-json-private-marker"))
        #expect(diagnostic.utf8.count <= 4_000)
        #expect(await setup.execution.callCount == 1)
    }

    private var ioRecoveryInspection: String {
        """
        {"findings":[{"id":"untrusted","priority":2,"path":"File0.swift","line":1,"side":"RIGHT",
        "body":"A concrete problem.","evidence":"Concrete support."}]}
        """
    }

    private var ioRecoveryTeam: [ReviewWorkerConfiguration] {
        reviewTestTeam().map { member in
            ReviewWorkerConfiguration(id: member.id, harnessID: member.harnessID, modelOptionID: member.modelOptionID,
                                      launchModel: member.launchModel, effort: member.effort, executablePath: "/bin/sh")
        }
    }

    private func ioRecoveryFixture(finalResponses: [String]) throws -> ReviewCoordinatorIORecoverySetup {
        let outcomes = try finalResponses.map { ReviewWorkerIOTestShellRunner.Outcome.ioFailure(
            try ReviewWorkerIOTestSupport.codexStream(finalText: $0)
        ) }
        return try ioRecoveryFixture(outcomes: outcomes)
    }

    private func ioRecoveryFixture(outcomes: [ReviewWorkerIOTestShellRunner.Outcome]) throws -> ReviewCoordinatorIORecoverySetup {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("review-io-history-tests-\(UUID().uuidString)")
        let store = ReviewTeamHistoryStore(rootDirectory: root)
        let execution = ReviewWorkerIOTestShellRunner(outcomes: outcomes)
        let executor = DefaultPullRequestReviewWorkerExecutor(
            environmentBuilder: ReviewWorkerTestEnvironmentBuilder(values: [:]), processRegistry: PullRequestReviewWorkerProcessRegistry(),
            capabilityShellRunner: ReviewWorkerIOTestShellRunner(outcomes: [.help]), executionShellRunner: execution
        )
        let fixture = try ReviewCoordinatorFixture(historyStore: store, workerOverride: { fallback in
            ReviewCoordinatorIORecoveryWorker(executor: executor, fallback: fallback)
        })
        return ReviewCoordinatorIORecoverySetup(fixture: fixture, store: store, root: root, execution: execution)
    }
}

private struct ReviewCoordinatorIORecoverySetup {
    let fixture: ReviewCoordinatorFixture
    let store: ReviewTeamHistoryStore
    let root: URL
    let execution: ReviewWorkerIOTestShellRunner
}

private struct ReviewCoordinatorIORecoveryWorker: PullRequestReviewWorkerExecuting {
    let executor: DefaultPullRequestReviewWorkerExecutor
    let fallback: ReviewCoordinatorWorker

    func preflight(_ configuration: ReviewWorkerConfiguration) async throws {
        if configuration.id == "lead" {
            try await executor.preflight(configuration)
        } else {
            try await fallback.preflight(configuration)
        }
    }

    // swiftlint:disable:next function_parameter_count
    func execute(configuration: ReviewWorkerConfiguration, packet: ReviewPacketLease, prompt: String,
                 runID: String, generation: Int, executionID: String) async throws -> String {
        let isInspection = !packet.fileNames.contains("candidates.json") && !packet.fileNames.contains("canonical.json")
        let worker: any PullRequestReviewWorkerExecuting = configuration.id == "lead" && isInspection ? executor : fallback
        return try await worker.execute(configuration: configuration, packet: packet, prompt: prompt,
                                        runID: runID, generation: generation, executionID: executionID)
    }

    func cancel(runID: String) async {
        await executor.cancel(runID: runID)
        await fallback.cancel(runID: runID)
    }
}
