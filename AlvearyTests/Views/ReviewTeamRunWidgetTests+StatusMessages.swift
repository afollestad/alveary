import AppKit
import Testing

@testable import Alveary

@MainActor
extension ReviewTeamRunWidgetTests {
    @Test
    func `status messages follow history with counts from each reviewers newest report`() throws {
        var run = failedRun(teamSize: 3)
        run.phase = .crossChecking
        run.failures = [:]
        run.error = nil
        run.inspections = [
            "lead": ReviewInspectionReport(findings: [candidate("l1", priority: 1), candidate("l2", priority: 2)]),
            "peer": ReviewInspectionReport(findings: []),
            "peer-2": ReviewInspectionReport(findings: [candidate("p1", priority: 2)])
        ]
        let findings = ["f1", "f2"].map {
            ReviewCanonicalFinding(id: $0, sourceCandidateIDs: [], path: "a.swift", line: 1, side: "RIGHT", body: "Body")
        }
        run.canonical = ReviewCanonicalReport(findings: findings)
        run.voteReports = ["lead": ReviewVoteReport(votes: [
            ReviewTeamVote(voterID: "lead", findingID: "f1", decision: .agree, priority: 1, rationale: "Yes."),
            ReviewTeamVote(voterID: "lead", findingID: "f2", decision: .disagree, priority: nil, rationale: "No.")
        ])]
        let history = [
            attempt("a1", "lead", .inspecting, .succeeded),
            attempt("a2", "peer", .inspecting, .invalid),
            attempt("a3", "peer", .inspecting, .succeeded),
            attempt("a4", "peer-2", .inspecting, .succeeded),
            attempt("a5", "lead", .consolidating, .succeeded),
            attempt("a6", "lead", .crossChecking, .succeeded),
            attempt("a7", "peer", .crossChecking, .running)
        ]
        run.history = history

        let messages = ReviewTeamStatusMessage.messages(for: run)

        #expect(messages.map(\.id) == history.map { "collective-review-message:run:\($0.id)" })
        #expect(messages.map(\.reviewerID) == ["lead", "peer", "peer", "peer-2", "lead", "lead", "peer"])
        #expect(messages.map(\.text) == [
            "Finished inspecting: 2 findings (1 P1, 1 P2).",
            "Returned an invalid response. Retrying.",
            "Finished inspecting: nothing to flag.",
            "Finished inspecting: 1 finding (1 P2).",
            "Merged 3 findings from 3 reviewers into 2.",
            "Cross-checked 2 findings: agreed with 1, disagreed with 1.",
            "Cross-checking 2 findings…"
        ])
        #expect(messages.map(\.state) == [.done, .done, .done, .done, .done, .done, .working])
        let roles = messages.compactMap { message -> String? in
            guard case .reviewer(_, let role) = message.author else { return nil }
            return role
        }
        #expect(roles == ["Lead", "Peer 1", "Peer 1", "Peer 2", "Lead", "Lead", "Peer 1"])
    }

    @Test
    func `status messages never credit an older attempt or hide a failure`() {
        var run = failedRun()
        run.history = [
            attempt("a1", "peer", .inspecting, .failed, error: String(repeating: "x", count: 300)),
            attempt("a2", "lead", .inspecting, .succeeded),
            attempt("a3", "lead", .inspecting, .succeeded, generation: 1),
            attempt("a4", "peer", .inspecting, .invalid, generation: 1)
        ]

        let messages = ReviewTeamStatusMessage.messages(for: run)

        #expect(messages.map(\.text) == [
            "Failed: " + String(repeating: "x", count: 239) + "…",
            "Finished inspecting.",
            "Finished inspecting: nothing to flag.",
            "Returned an invalid response."
        ])
        #expect(messages.map(\.state) == [.failed, .done, .done, .failed])
    }

    @Test
    func `the team line reports consensus once the cross-check settles`() {
        var run = pausedRun(phase: .crossChecking)
        run.history = []
        #expect(ReviewTeamStatusMessage.messages(for: run).isEmpty)

        run.phase = .staged
        run.accepted = [ReviewAcceptedFinding(finding: ReviewCoordinatorWorker.canonicalFinding, priority: 2, votes: [])]
        let consensus = ReviewTeamStatusMessage.messages(for: run)
        #expect(consensus.map(\.text) == ["1 of 1 finding reached the 2/3 majority."])
        #expect(consensus.first?.author == .team)
        #expect(consensus.first?.reviewerID == nil)

        run.phase = .completed
        run.canonical = nil
        run.accepted = []
        run.inspections = Dictionary(uniqueKeysWithValues: run.team.map { ($0.id, ReviewInspectionReport(findings: [])) })
        #expect(ReviewTeamStatusMessage.messages(for: run).map(\.text) == ["No reviewer found anything to flag."])
    }

    @Test
    func `the card hands reviewer status to the messages only with a complete history`() {
        let history = [attempt("a1", "lead", .inspecting, .succeeded)]
        for (history, isPartial) in [(nil, nil), (history, true), (history, nil)] as [([ReviewTeamAttempt]?, Bool?)] {
            var run = failedRun()
            run.history = history
            run.historyIsPartial = isPartial
            let carriesStatus = history != nil && isPartial == nil
            let view = AppKitReviewTeamRunWidgetView()
            view.configure(.init(run: run, typography: TranscriptTypography()))

            #expect(reviewTeamDescendants(of: AppKitReviewTeamReviewerRowView.self, in: view).count == (carriesStatus ? 0 : run.team.count))
            #expect(ReviewTeamStatusMessage.messages(for: run).isEmpty == !carriesStatus)
        }
    }

    @Test
    func `status messages follow their card and open that reviewers details`() throws {
        var run = failedRun()
        run.history = [attempt("a1", "peer", .inspecting, .failed, error: "Timed out.")]
        let entry = HostToolWidgetEntry(
            id: "card", toolName: "Collective review", content: .collectiveReviewRun(run), isComplete: true, isError: true
        )
        let rows = AppKitTranscriptRowFactory().makeRows(
            for: [.hostToolWidget(id: "card", entry: entry), .assistantMessage(id: "next", text: "Done.")],
            configuration: .init()
        )
        #expect(rows.map(\.id) == ["card", "collective-review-message:run:a1", "next"])
        let row = try #require(rows[1].view as? AppKitTranscriptReviewTeamMessageRowView)
        row.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        row.layoutSubtreeIfNeeded()
        #expect(row.intrinsicContentSize.height > 0)

        let receipt = ReviewRunActionReceipt()
        let observer = NotificationCenter.default.addObserver(forName: .reviewTeamDetailsRequested, object: row, queue: .main) { note in
            let selectedRun = note.userInfo?["run"] as? ReviewTeamRun
            let reviewerID = note.userInfo?["reviewerID"] as? String
            MainActor.assumeIsolated {
                receipt.run = selectedRun
                receipt.reviewerID = reviewerID
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }
        let bubble = try #require(reviewTeamDescendants(of: AppKitHostToolWidgetBubbleView.self, in: row).first)
        #expect(bubble.accessibilityRole() == .button)
        #expect(bubble.acceptsFirstResponder)
        #expect(bubble.accessibilityLabel()?.hasSuffix(", Peer 1: Failed: Timed out.") == true)
        #expect(bubble.accessibilityPerformPress())
        #expect(receipt.run == run)
        #expect(receipt.reviewerID == "peer")
    }
}

private extension ReviewTeamRunWidgetTests {
    func attempt(
        _ id: String,
        _ reviewerID: String,
        _ phase: ReviewTeamRun.Phase,
        _ status: ReviewTeamAttempt.Status,
        generation: Int = 0,
        error: String? = nil
    ) -> ReviewTeamAttempt {
        ReviewTeamAttempt(
            id: id, reviewerID: reviewerID, phase: phase, generation: generation, startedAt: Date(timeIntervalSince1970: 1_000),
            packetHash: "packet", prompt: ReviewHistoryArtifact(id: "prompt", name: "prompt.txt", byteCount: 1), inputs: [],
            status: status, error: error
        )
    }

    func candidate(_ id: String, priority: Int) -> ReviewCandidate {
        ReviewCandidate(id: id, priority: priority, path: "a.swift", line: 1, side: "RIGHT", body: "Body", evidence: "Evidence")
    }
}
