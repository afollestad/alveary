import Foundation
import SwiftData
import Testing

@testable import Alveary

@MainActor
final class ReviewCoordinatorFixture {
    let container: ModelContainer
    let conversation: Conversation
    let service = StubPullRequestsService()
    let worker = ReviewCoordinatorWorker()
    let coordinator: PullRequestReviewTeamCoordinator
    let packets: ReviewPacketStore
    let packetRoot: URL
    let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)

    init(ownPR: Bool = false, historyStore: ReviewTeamHistoryStore? = nil,
         commitSave: @escaping (ModelContext) throws -> Void = { try $0.save() }) throws {
        container = try ModelContainer(for: Project.self, AgentThread.self, Conversation.self, ConversationEventRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        let thread = AgentThread(name: "Review team")
        conversation = Conversation(id: UUID().uuidString, provider: "codex", thread: thread)
        context.insert(thread)
        context.insert(conversation)
        try context.save()
        var detail = makePullRequestDetail(id: identifier)
        detail.viewerLogin = ownPR ? detail.authorLogin : "reviewer"
        detail.baseRefOid = "base"
        detail.headRefOid = "head"
        service.detailResult = .success(detail)
        service.diffSnapshotResult = .success(try PullRequestDiffSnapshot.make(
            text: makeUnifiedDiffFixture(fileCount: 1), baseOID: "base", headOID: "head"
        ))
        packetRoot = FileManager.default.temporaryDirectory.appendingPathComponent("collective-tests-\(UUID().uuidString)")
        packets = ReviewPacketStore(rootDirectory: packetRoot)
        coordinator = PullRequestReviewTeamCoordinator(
            modelContext: context, service: service, worker: worker, packets: packets,
            staging: PullRequestCollectiveReviewStagingService(modelContext: context, service: service),
            activity: PullRequestAgenticThreadActivity(currentSignal: { _ in .neutral }),
            resolver: PullRequestReviewTeamResolver(providerDiscovery: RecordingProviderDiscoveryService(statuses: [:])),
            cancellationStore: ReviewTeamCancellationStore(rootDirectory: packetRoot.appendingPathComponent("cancellations")),
            historyStore: historyStore,
            commitSave: commitSave
        )
    }

    deinit { try? FileManager.default.removeItem(at: packetRoot) }

    func start() throws {
        try coordinator.begin(conversationID: conversation.id, identifier: identifier,
                              url: URL(string: "https://github.com/octo/alpha/pull/7")!, team: reviewTestTeam(), criteria: "Find bugs.")
    }

    func makeRun(
        prior: PullRequestCollectiveReviewStagingSnapshot? = nil,
        conversationID: String? = nil,
        runID: String = UUID().uuidString
    ) throws -> ReviewTeamRun {
        let snapshot = try prior ?? coordinator.staging.snapshot(for: identifier, editState: nil)
        return ReviewTeamRun(
            payloadVersion: 1, id: runID, proposalID: UUID().uuidString, conversationID: conversationID ?? conversation.id,
            identifier: identifier, url: URL(string: "https://github.com/octo/alpha/pull/7")!, team: reviewTestTeam(),
            criteria: "Find bugs.", priorProposal: snapshot, createdAt: .now, generation: 0, phase: .preparing,
            inspections: [:], voteReports: [:], accepted: [], attempts: [:], failures: [:], supersededProposalIDs: []
        )
    }

    func terminalRun() async throws -> ReviewTeamRun {
        try await wait { self.coordinator.runs[self.conversation.id]?.phase.isWorking == false }
        return try #require(coordinator.runs[conversation.id])
    }

    /// Release and join held work before fixture teardown when an intermediate requirement throws.
    func withPipelineCleanup(
        _ task: Task<Void, Never>,
        gate: PullRequestsServiceGate,
        operation: @MainActor () async throws -> Void
    ) async throws {
        do {
            try await operation()
        } catch {
            task.cancel()
            gate.open()
            do {
                try await waitForCompletion(of: task)
            } catch {
                Issue.record(error)
            }
            throw error
        }
    }

    /// Fake worker completion precedes pipeline result handling; observe the original scheduled task instead.
    func waitForCompletion(of task: Task<Void, Never>) async throws {
        let completion = ReviewCoordinatorTaskCompletion()
        let observer = Task {
            await task.value
            completion.finished = true
        }
        defer {
            task.cancel()
            observer.cancel()
        }
        try await wait { completion.finished }
    }

    func wait(_ condition: @MainActor () async -> Bool) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(8))
        while !(await condition()) {
            guard clock.now < deadline else { throw ReviewTeamError.invalidOutput("Test timed out waiting for review state.") }
            await Task.yield()
        }
    }
}

actor ReviewCoordinatorWorker: PullRequestReviewWorkerExecuting {
    struct Call: Sendable {
        let memberID: String
        let phase: String
        let files: [String]
        let hash: String
    }

    static let canonicalFinding = ReviewCanonicalFinding(
        id: "finding-1", sourceCandidateIDs: [], path: "File0.swift", line: 1, side: "RIGHT", body: "A concrete problem."
    )
    private(set) var calls: [Call] = []
    private(set) var completedCount = 0
    private(set) var cancelledRunIDs: [String] = []
    private var gate: PullRequestsServiceGate?
    private var empty = false
    private var malformedFirst = false
    private var failedInspectors: Set<String> = []
    private var failedVoters: Set<String> = []

    var inspectionCount: Int { calls.filter { $0.phase == "inspection" }.count }

    func configure(gate: PullRequestsServiceGate? = nil, empty: Bool = false, malformedFirst: Bool = false,
                   failedInspectors: Set<String> = [], failedVoters: Set<String> = []) {
        self.gate = gate
        self.empty = empty
        self.malformedFirst = malformedFirst
        self.failedInspectors = failedInspectors
        self.failedVoters = failedVoters
    }

    func preflight(_ configuration: ReviewWorkerConfiguration) async throws {}
    func cancel(runID: String) async { cancelledRunIDs.append(runID) }

    // Mirrors the production executor protocol.
    // swiftlint:disable:next function_parameter_count
    func execute(configuration: ReviewWorkerConfiguration, packet: ReviewPacketLease, prompt: String,
                 runID: String, generation: Int, executionID: String) async throws -> String {
        let phase = packet.fileNames.contains("canonical.json")
            ? "votes" : packet.fileNames.contains("candidates.json") ? "consolidation" : "inspection"
        calls.append(Call(memberID: configuration.id, phase: phase, files: packet.fileNames, hash: packet.inputHash))
        defer { completedCount += 1 }
        switch phase {
        case "consolidation":
            let candidateURL = packet.directoryURL.appendingPathComponent("candidates.json")
            let candidates = try JSONDecoder().decode([ReviewCandidate].self, from: Data(contentsOf: candidateURL))
            return try json(ReviewCanonicalReport(findings: [ReviewCanonicalFinding(
                id: "finding-1", sourceCandidateIDs: candidates.map(\.id), path: "File0.swift", line: 1, side: "RIGHT", body: "A concrete problem."
            )]))
        case "votes":
            if failedVoters.contains(configuration.id) { throw ReviewTeamError.invalidOutput("Provider timed out after 300 seconds") }
            return try json(ReviewVoteReport(votes: [ReviewTeamVote(
                voterID: "untrusted", findingID: "finding-1", decision: .agree,
                priority: configuration.id == "lead" ? 0 : 2, rationale: "Verified against the diff."
            )]))
        default:
            await gate?.wait()
            if failedInspectors.contains(configuration.id) { throw ReviewTeamError.invalidOutput("Provider failed") }
            if malformedFirst, configuration.id == "lead" {
                malformedFirst = false
                return "malformed"
            }
            return try json(ReviewInspectionReport(findings: empty ? [] : [ReviewCandidate(
                id: "untrusted", priority: 2, path: "File0.swift", line: 1, side: "RIGHT",
                body: "A concrete problem.", evidence: "Concrete support."
            )]))
        }
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        try ReviewTeamDigest.jsonString(value)
    }
}

@MainActor
private final class ReviewCoordinatorTaskCompletion {
    var finished = false
}
