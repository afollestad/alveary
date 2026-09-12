import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension SnapshotTests {
    func testCollectiveReviewInspectionActivity() throws {
        let fixture = try ConversationViewModelTestFixture()
        let chat = ReviewTeamConversationTestFixture.chatView(fixture: fixture, isWorking: true)
        var run = CollectiveReviewSnapshotFixture.progressRun()
        run.phase = .inspecting
        run.inspections = ["lead": ReviewInspectionReport(findings: [])]
        run.canonical = nil
        run.voteReports = [:]
        let entry = CollectiveReviewSnapshotFixture.widgetEntry(run: run)
        let transcript = AppKitTranscriptScrollViewRepresentable(
            items: [.hostToolWidget(id: entry.id, entry: entry)],
            transientRows: .init(isTurnActive: true, isThinkingAnimated: false),
            rowConfiguration: .init(bubbleMaxWidth: 760)
        )
        let composer = AppKitChatComposerPanelConfiguration(
            bodyConfiguration: chat.composerBodyConfiguration,
            actionRowConfiguration: chat.composerActionRowConfiguration(usageSummary: .unreported),
            showsTopDivider: false,
            layout: .init(
                horizontalPadding: ChatComposerPanelLayout.appKitHorizontalPadding,
                topContentSpacing: ChatComposerPanelLayout.topContentSpacing,
                actionRowSpacing: ChatComposerPanelLayout.actionRowSpacing,
                bottomPadding: ChatComposerPanelLayout.nativeActionRowBottomPadding
            )
        )

        assertMacSnapshot(
            AppKitChatSurfaceRepresentable(content: AnyView(transcript), composerConfiguration: composer),
            size: CGSize(width: 900, height: 560), named: "collective_review_inspection_activity", colorScheme: .dark
        )
    }

    func testCollectiveReviewProgressWidget() {
        assertMacSnapshot(
            appKitRowSnapshot {
                CollectiveReviewSnapshotFixture.widgetRow(
                    run: CollectiveReviewSnapshotFixture.progressRun()
                )
            },
            size: CGSize(width: 700, height: 330),
            named: "collective_review_progress"
        )
    }

    func testCollectiveReviewFailureWidget() {
        assertMacSnapshot(
            appKitRowSnapshot {
                CollectiveReviewSnapshotFixture.expandedFailureWidgetRow()
            },
            size: CGSize(width: 700, height: 740),
            named: "collective_review_failure"
        )
    }

    func testCollectiveReviewNotProposedDisclosure() {
        assertMacSnapshot(
            appKitRowSnapshot {
                var run = CollectiveReviewSnapshotFixture.decisionRun()
                run.accepted = []
                return CollectiveReviewSnapshotFixture.widgetRow(run: run)
            },
            size: CGSize(width: 700, height: 300),
            named: "collective_review_not_proposed_disclosure",
            colorScheme: .dark
        )
    }

    func testCollectiveReviewPausedInspectionWidget() {
        assertMacSnapshot(
            appKitRowSnapshot { CollectiveReviewSnapshotFixture.widgetRow(run: CollectiveReviewSnapshotFixture.pausedRun(phase: .inspecting)) },
            size: CGSize(width: 700, height: 440), named: "collective_review_paused_inspection"
        )
    }

    func testCollectiveReviewPausedCrossCheckWidget() {
        assertMacSnapshot(
            appKitRowSnapshot { CollectiveReviewSnapshotFixture.widgetRow(run: CollectiveReviewSnapshotFixture.pausedRun(phase: .crossChecking)) },
            size: CGSize(width: 700, height: 440), named: "collective_review_paused_cross_check"
        )
    }

    func testCollectiveReviewPausedRunDetails() {
        assertMacSnapshot(
            ReviewTeamRunDetailsSheet(initialRun: CollectiveReviewSnapshotFixture.pausedRun(phase: .crossChecking), onClose: {}),
            size: CGSize(width: 780, height: 690), named: "collective_review_paused_details"
        )
    }

    func testCollectiveReviewRunDetailsOverview() {
        assertMacSnapshot(
            ReviewTeamRunDetailsSheet(initialRun: CollectiveReviewSnapshotFixture.progressRun(), onClose: {}),
            size: CGSize(width: 780, height: 690), named: "collective_review_run_overview"
        )
    }

    func testCollectiveReviewRunDecisions() {
        assertMacSnapshot(
            ReviewTeamRunDecisions(run: CollectiveReviewSnapshotFixture.decisionRun()).padding(24),
            size: CGSize(width: 780, height: 600), named: "collective_review_decisions"
        )
    }

    func testCollectiveReviewRunActivity() {
        assertMacSnapshot(
            ReviewTeamRunActivity(run: CollectiveReviewSnapshotFixture.historyRun(), store: nil,
                                  reviewerID: .constant("lead")).padding(24),
            size: CGSize(width: 780, height: 430), named: "collective_review_activity"
        )
    }
}

@MainActor
private enum CollectiveReviewSnapshotFixture {
    static let identifier = PullRequestIdentifier(owner: "octo", repo: "alpha", number: 7)
    static let finding = ReviewCanonicalFinding(
        id: "finding-1",
        sourceCandidateIDs: ["lead:1", "peer-1:1"],
        path: "Sources/Retry.swift",
        line: 42,
        side: "RIGHT",
        body: "The retry path never reaches a terminal failure."
    )

    static let team = [
        ReviewWorkerConfiguration(
            id: "lead",
            providerID: "codex",
            modelOptionID: "gpt-5",
            launchModel: "gpt-5",
            effort: "high",
            executablePath: "/fake/codex"
        ),
        ReviewWorkerConfiguration(
            id: "peer-1",
            providerID: "claude",
            modelOptionID: "sonnet",
            launchModel: "sonnet",
            effort: "high",
            executablePath: "/fake/claude"
        ),
        ReviewWorkerConfiguration(
            id: "peer-2",
            providerID: "codex",
            modelOptionID: "o3",
            launchModel: "o3",
            effort: "medium",
            executablePath: "/fake/codex"
        )
    ]

    static func progressRun() -> ReviewTeamRun {
        makeRun(
            phase: .crossChecking,
            voteReports: [
                "lead": ReviewVoteReport(votes: [vote(voterID: "lead", decision: .agree)])
            ]
        )
    }

    static func failureRun() -> ReviewTeamRun {
        makeRun(
            phase: .failed,
            voteReports: [
                "lead": ReviewVoteReport(votes: [vote(voterID: "lead", decision: .agree)])
            ],
            failures: [
                "crossChecking:peer-1": "The reviewer returned an invalid vote report after one corrective retry.",
                "crossChecking:peer-2": "The reviewer timed out after five minutes without a valid response."
            ],
            error: ReviewTeamError.quorumRequired(2).localizedDescription
        )
    }

    static func pausedRun(phase: ReviewTeamRun.Phase) -> ReviewTeamRun {
        var run = makeRun(
            phase: .awaitingDecision,
            voteReports: [
                "lead": ReviewVoteReport(votes: [vote(voterID: "lead", decision: .agree)]),
                "peer-1": ReviewVoteReport(votes: [vote(voterID: "peer-1", decision: .agree)])
            ],
            failures: ["\(phase.rawValue):peer-2": "The reviewer timed out after five minutes without a valid response."]
        )
        run.pausedPhase = phase
        if phase == .inspecting {
            run.inspections.removeValue(forKey: "peer-2")
            run.canonical = nil
            run.voteReports = [:]
        }
        return run
    }

    static func decisionRun() -> ReviewTeamRun {
        var run = failureRun()
        run.phase = .staged
        run.failures = [:]
        run.error = nil
        run.voteReports = [
            "lead": ReviewVoteReport(votes: [vote(voterID: "lead", decision: .agree)]),
            "peer-1": ReviewVoteReport(votes: [vote(voterID: "peer-1", decision: .disagree)]),
            "peer-2": ReviewVoteReport(votes: [vote(voterID: "peer-2", decision: .agree)])
        ]
        run.accepted = [ReviewAcceptedFinding(finding: finding, priority: 1, votes: run.voteReports.values.flatMap(\.votes))]
        return run
    }

    static func historyRun() -> ReviewTeamRun {
        var run = progressRun()
        let prompt = ReviewHistoryArtifact(id: "prompt", name: "prompt.txt", byteCount: 120)
        run.history = [
            ReviewTeamAttempt(id: "a1", reviewerID: "lead", phase: .inspecting, generation: 0,
                              startedAt: run.createdAt, packetHash: "packet", prompt: prompt, inputs: [],
                              finishedAt: run.createdAt.addingTimeInterval(42), status: .invalid, error: "Expected a findings array."),
            ReviewTeamAttempt(id: "a2", reviewerID: "lead", phase: .inspecting, generation: 0,
                              startedAt: run.createdAt.addingTimeInterval(43), packetHash: "packet", prompt: prompt, inputs: [],
                              finishedAt: run.createdAt.addingTimeInterval(76), status: .succeeded),
            ReviewTeamAttempt(id: "a3", reviewerID: "lead", phase: .crossChecking, generation: 0,
                              startedAt: run.createdAt.addingTimeInterval(90), packetHash: "packet", prompt: prompt,
                              inputs: [], status: .running)
        ]
        return run
    }

    static func widgetRow(run: ReviewTeamRun) -> AppKitTranscriptHostToolWidgetRowView {
        let view = AppKitTranscriptHostToolWidgetRowView()
        view.configure(.init(entry: widgetEntry(run: run), bubbleMaxWidth: 640))
        return view
    }

    static func widgetEntry(run: ReviewTeamRun) -> HostToolWidgetEntry {
        HostToolWidgetEntry(
            id: "collective-review-run:\(run.id)",
            toolName: "Collective review",
            content: .collectiveReviewRun(run),
            isComplete: !run.phase.isWorking,
            isError: run.phase == .failed
        )
    }

    static func expandedFailureWidgetRow() -> AppKitTranscriptHostToolWidgetRowView {
        let row = widgetRow(run: failureRun())
        firstButton(in: row, titled: "Show 1 not proposed")?.performClick(nil)
        return row
    }

    private static func makeRun(
        phase: ReviewTeamRun.Phase,
        voteReports: [String: ReviewVoteReport],
        failures: [String: String] = [:],
        error: String? = nil
    ) -> ReviewTeamRun {
        ReviewTeamRun(
            payloadVersion: 1,
            id: "snapshot-run",
            proposalID: "snapshot-proposal",
            conversationID: "snapshot-conversation",
            identifier: identifier,
            url: URL(string: "https://github.com/octo/alpha/pull/7")!,
            team: team,
            criteria: "Review correctness and regressions.",
            priorProposal: PullRequestCollectiveReviewStagingSnapshot(
                proposalOwnerConversationID: nil,
                proposalID: nil,
                proposalContentHash: nil,
                editState: nil
            ),
            createdAt: Date(timeIntervalSince1970: 1_700_000_000),
            generation: 0,
            phase: phase,
            baseOID: "base",
            headOID: "head",
            inputHash: "packet",
            inspections: Dictionary(uniqueKeysWithValues: team.map {
                ($0.id, ReviewInspectionReport(findings: []))
            }),
            canonical: ReviewCanonicalReport(findings: [finding]),
            voteReports: voteReports,
            accepted: [],
            attempts: [:],
            failures: failures,
            error: error,
            resultHash: nil,
            supersededProposalIDs: []
        )
    }

    private static func vote(
        voterID: String,
        decision: ReviewTeamVote.Decision
    ) -> ReviewTeamVote {
        ReviewTeamVote(
            voterID: voterID,
            findingID: finding.id,
            decision: decision,
            priority: decision == .agree ? 1 : nil,
            rationale: decision == .agree
                ? "The loop has no bounded exit."
                : "The caller applies a separate retry budget."
        )
    }

    private static func firstButton(in view: NSView, titled title: String) -> NSButton? {
        if let button = view as? NSButton, button.title == title {
            return button
        }
        return view.subviews.lazy.compactMap { firstButton(in: $0, titled: title) }.first
    }
}
