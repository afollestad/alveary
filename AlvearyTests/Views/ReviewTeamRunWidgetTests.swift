import AppKit
import Testing

@testable import Alveary

@MainActor
struct ReviewTeamRunWidgetTests {
    @Test
    func `vote disclosure is an accessible button and includes missing reviewers`() throws {
        let reviewers = testReviewers()
        let evidence = PullRequestReviewProposalRecord.CommentEvidence(
            findingID: "finding",
            sourceCandidateIDs: ["candidate"],
            priority: 1,
            votes: [
                ReviewTeamVote(
                    voterID: "lead",
                    findingID: "finding",
                    decision: .agree,
                    priority: 1,
                    rationale: "Confirmed the failure path."
                )
            ],
            reviewers: reviewers
        )
        let view = AppKitReviewProposalVoteEvidenceView()
        view.configure(evidence: evidence, reviewers: reviewers, typography: TranscriptTypography())

        let button = try #require(descendants(of: AppKitTranscriptHeaderToggleButton.self, in: view).first)
        #expect(button.title == "1/2 agreed")
        #expect(button.accessibilityRole() == .button)
        #expect(button.accessibilityLabel() == "1 of 2 reviewers agreed. Show vote details")
        #expect(button.target != nil && button.action != nil)
        #expect(button.font == TranscriptTypography().nsFont(.caption, weight: .medium))

        button.performClick(nil)
        let labels = descendants(of: NSTextField.self, in: view).map(\.stringValue)
        #expect(labels.contains { $0.contains("Confirmed the failure path.") })
        #expect(labels.contains { $0.contains("Failed / no valid vote") })
    }

    @Test
    func `not proposed disclosure expands and collapses without action button chrome`() throws {
        var run = pausedRun(phase: .crossChecking)
        run.phase = .staged
        let view = AppKitReviewTeamRunWidgetView()
        var invalidations = 0
        view.onHeightInvalidated = { invalidations += 1 }
        view.configure(.init(run: run, typography: TranscriptTypography()))

        let expand = try #require(descendants(of: AppKitTranscriptHeaderToggleButton.self, in: view).first)
        #expect(expand.title == "Show 1 not proposed")
        #expect(expand.accessibilityLabel() == "Show findings not proposed")
        expand.performClick(nil)
        #expect(invalidations == 1)

        let collapse = try #require(descendants(of: AppKitTranscriptHeaderToggleButton.self, in: view).first)
        #expect(collapse.title == "Hide 1 not proposed")
        #expect(collapse.accessibilityLabel() == "Hide findings not proposed")
        collapse.performClick(nil)
        #expect(invalidations == 2)
        #expect(descendants(of: AppKitReviewProposalVoteEvidenceView.self, in: view).isEmpty)
    }

    @Test
    func `failed reviewer exposes its diagnostic and retry is accessible`() throws {
        let view = AppKitReviewTeamRunWidgetView()
        view.configure(.init(run: failedRun(), typography: TranscriptTypography()))

        let labels = descendants(of: NSView.self, in: view).compactMap { $0.accessibilityLabel() }
        #expect(labels.contains { $0.contains("timed out after five minutes") })
        let retry = try #require(descendants(of: NSButton.self, in: view).first { $0.title == "Retry failed reviewers" })
        #expect(retry.accessibilityRole() == .button)
        #expect(retry.accessibilityLabel() == "Retry failed reviewers")
        #expect(retry.target != nil && retry.action != nil)
    }

    @Test
    func `a run requiring new input cannot be retried`() {
        let view = AppKitReviewTeamRunWidgetView()
        var run = failedRun()
        run.requiresNewRun = true
        view.configure(.init(run: run, typography: TranscriptTypography()))

        #expect(descendants(of: NSButton.self, in: view).allSatisfy { $0.title != "Retry review" })
    }

    @Test
    func `run details remain available while working and after completion`() throws {
        for phase in [ReviewTeamRun.Phase.inspecting, .staged, .cancelled] {
            let view = AppKitReviewTeamRunWidgetView()
            var run = failedRun()
            run.phase = phase
            view.configure(.init(run: run, typography: TranscriptTypography()))
            let buttons = descendants(of: NSButton.self, in: view)
            let details = try #require(buttons.first { $0.title == "Run details" })
            #expect(details.isEnabled && details.action != nil)
            #expect(buttons.filter { $0.title == "Details" }.map(\.tag) == [0, 1])
        }
    }

    @Test
    func `incomplete cross checks are pending not rejected until terminal`() {
        var run = failedRun()
        let finding = ReviewCanonicalFinding(id: "f", sourceCandidateIDs: ["c"], path: "a.swift", line: 1,
                                             side: "RIGHT", body: "Check the retry.")
        run.phase = .crossChecking
        #expect(ReviewTeamRunPresentation.decision(finding, in: run) == "0/2 agreed · Decision pending")
        run.phase = .failed
        #expect(ReviewTeamRunPresentation.decision(finding, in: run) == "Not proposed · Insufficient complete cross-checks")
    }

    @Test
    func `partial team completion is explicit but a full review has no warning`() {
        var run = failedRun()
        #expect(run.partialCompletionWarning == nil)
        run.phase = .staged
        #expect(run.partialCompletionWarning?.contains("1/2 inspections completed") == true)
        run.inspections["peer"] = ReviewInspectionReport(findings: [])
        #expect(run.partialCompletionWarning == nil)
    }

    @Test(arguments: [ReviewTeamRun.Phase.inspecting, .crossChecking])
    func `paused review offers retry continue and cancel without rejecting findings`(phase: ReviewTeamRun.Phase) throws {
        let run = pausedRun(phase: phase)
        let view = AppKitReviewTeamRunWidgetView()
        view.configure(.init(run: run, typography: TranscriptTypography()))

        let buttons = descendants(of: NSButton.self, in: view)
        let expected = ["Run details", "Retry failed reviewers", "Continue with majority", "Cancel review"]
        for title in expected {
            let button = try #require(buttons.first { $0.title == title })
            #expect(button.isEnabled)
            #expect(button.accessibilityRole() == .button)
            #expect(button.accessibilityLabel() == title)
            #expect(button.target != nil && button.action != nil)
        }
        #expect(!buttons.contains { $0.title == "Retry review" || $0.title.contains("not proposed") })
        let next = phase == .inspecting ? "then consolidates and cross-checks any findings" : "prepares a proposal from the completed votes"
        let labels = descendants(of: NSTextField.self, in: view).map(\.stringValue)
        #expect(labels.contains { $0.contains(next) && $0.contains("Nothing is submitted automatically") })
        #expect(labels.contains { $0.contains("— Failed") })
        #expect(!labels.contains { $0.contains("Cross-checking…") || $0 == "Waiting" })
        let primary = try #require(buttons.first { $0.title == "Continue with majority" } as? AppKitTranscriptApprovalButton)
        #expect(primary.actionStyle == .primary)
        #expect(primary.action == NSSelectorFromString("continueWithMajority"))
    }

    @Test
    func `continue button sends the displayed run identity to the app`() throws {
        let run = pausedRun(phase: .crossChecking)
        let view = AppKitReviewTeamRunWidgetView()
        view.configure(.init(run: run, typography: TranscriptTypography()))
        let receipt = ReviewRunActionReceipt()
        let observer = NotificationCenter.default.addObserver(forName: .reviewTeamContinueRequested, object: view, queue: .main) { note in
            let conversationID = note.userInfo?["conversationID"] as? String
            let runID = note.userInfo?["runID"] as? String
            let generation = note.userInfo?["generation"] as? Int
            MainActor.assumeIsolated {
                receipt.conversationID = conversationID
                receipt.runID = runID
                receipt.generation = generation
            }
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        try #require(descendants(of: NSButton.self, in: view).first { $0.title == "Continue with majority" }).performClick(nil)

        #expect(receipt.conversationID == run.conversationID)
        #expect(receipt.runID == run.id)
        #expect(receipt.generation == run.generation)
    }

    @Test
    func `paused canonical decisions remain pending and continuing requires a majority`() {
        var run = pausedRun(phase: .crossChecking)
        let finding = run.canonical!.findings[0]
        #expect(ReviewTeamRunPresentation.decision(finding, in: run) == "2/3 agreed · Decision pending")
        run.voteReports.removeValue(forKey: "peer-2")
        run.failures["crossChecking:peer-2"] = "No valid report"
        let view = AppKitReviewTeamRunWidgetView()
        view.configure(.init(run: run, typography: TranscriptTypography()))
        #expect(!descendants(of: NSButton.self, in: view).contains { $0.title == "Continue with majority" })
    }

    @Test(arguments: [ReviewTeamRun.Phase.crossChecking, .staged])
    func `successful cross-check retains earlier inspection failure only as detail`(phase: ReviewTeamRun.Phase) throws {
        var run = pausedRun(phase: .crossChecking)
        run.phase = phase
        run.inspections.removeValue(forKey: "peer-2")
        run.failures["inspecting:peer-2"] = "Timed out after five minutes."
        let member = try #require(run.team.first { $0.id == "peer-2" })

        let status = ReviewTeamRunPresentation.status(for: member, in: run)

        #expect(status.label == "Cross-checked")
        #expect(status.detail == "Earlier inspection failed: Timed out after five minutes.")
        #expect(!status.failed)
    }

    private func pausedRun(phase: ReviewTeamRun.Phase) -> ReviewTeamRun {
        var run = failedRun(teamSize: 3)
        run.phase = .awaitingDecision
        run.pausedPhase = phase
        run.error = nil
        run.inspections["peer-2"] = ReviewInspectionReport(findings: [])
        if phase == .crossChecking {
            run.inspections["peer"] = ReviewInspectionReport(findings: [])
            run.canonical = ReviewCanonicalReport(findings: [ReviewCoordinatorWorker.canonicalFinding])
            run.voteReports = Dictionary(uniqueKeysWithValues: ["lead", "peer-2"].map { id in
                (id, ReviewVoteReport(votes: [ReviewTeamVote(
                    voterID: id, findingID: ReviewCoordinatorWorker.canonicalFinding.id,
                    decision: .agree, priority: 2, rationale: "Confirmed."
                )]))
            })
            run.failures = ["crossChecking:peer": "The reviewer timed out after five minutes."]
        }
        return run
    }

    private func testReviewers() -> [PullRequestReviewProposalRecord.Reviewer] {
        [
            PullRequestReviewProposalRecord.Reviewer(id: "lead", providerID: "codex", modelOptionID: "gpt-5"),
            PullRequestReviewProposalRecord.Reviewer(id: "peer", providerID: "claude", modelOptionID: "sonnet")
        ]
    }

    private func failedRun(teamSize: Int = 2) -> ReviewTeamRun {
        var team = [
            ReviewWorkerConfiguration(
                id: "lead",
                providerID: "codex",
                modelOptionID: "gpt-5",
                launchModel: "gpt-5",
                effort: "high",
                executablePath: "/fake/codex"
            ),
            ReviewWorkerConfiguration(
                id: "peer",
                providerID: "claude",
                modelOptionID: "sonnet",
                launchModel: "sonnet",
                effort: "high",
                executablePath: "/fake/claude"
            )
        ]
        if teamSize == 3 {
            team.append(ReviewWorkerConfiguration(
                id: "peer-2", providerID: "codex", modelOptionID: "gpt-6-astra", launchModel: "gpt-6-astra",
                effort: "max", executablePath: "/fake/codex"
            ))
        }
        return ReviewTeamRun(
            payloadVersion: 1,
            id: "run",
            proposalID: "proposal",
            conversationID: "conversation",
            identifier: PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7),
            url: URL(string: "https://github.com/octo/alpha/pull/7")!,
            team: team,
            criteria: "Review correctness.",
            priorProposal: PullRequestCollectiveReviewStagingSnapshot(
                proposalOwnerConversationID: nil,
                proposalID: nil,
                proposalContentHash: nil,
                editState: nil
            ),
            createdAt: Date(timeIntervalSince1970: 1_000),
            generation: 0,
            phase: .failed,
            inspections: ["lead": ReviewInspectionReport(findings: [])],
            voteReports: [:],
            accepted: [],
            attempts: [:],
            failures: ["inspecting:peer": "The reviewer timed out after five minutes."],
            error: "A reviewer failed.",
            supersededProposalIDs: []
        )
    }
}

@MainActor
private final class ReviewRunActionReceipt {
    var conversationID: String?
    var runID: String?
    var generation: Int?
}

@MainActor
private func descendants<View: NSView>(of type: View.Type, in view: NSView) -> [View] {
    view.subviews.flatMap { subview in
        let nested = descendants(of: type, in: subview)
        return (subview as? View).map { [$0] + nested } ?? nested
    }
}
