import Foundation
import Testing

@testable import Alveary

struct ReviewTeamConsensusTests {
    @Test(arguments: [2, 3, 4, 5])
    func `quorum is always the configured majority`(count: Int) {
        #expect(ReviewTeamConsensus.requiredVotes(teamSize: count) == count / 2 + 1)
    }

    @Test
    func `inspection assigns identities and requires exact anchors`() throws {
        let report = ReviewInspectionReport(findings: [candidate()])
        let parsed = try ReviewTeamConsensus.inspection(json(report), files: files)
        #expect(parsed.findings.first?.id != "untrusted")
        #expect(throws: ReviewTeamError.self) {
            try ReviewTeamConsensus.inspection(json(ReviewInspectionReport(findings: [candidate(line: 99)])), files: files)
        }
        #expect(throws: ReviewTeamError.self) {
            try ReviewTeamConsensus.inspection(
                json(ReviewInspectionReport(findings: [candidate(evidence: " \n ")])),
                files: files
            )
        }
    }

    @Test
    func `inspection identities are opaque and unique`() throws {
        let report = ReviewInspectionReport(findings: [candidate(), candidate()])
        let first = try ReviewTeamConsensus.inspection(json(report), files: files).findings.map(\.id)
        let second = try ReviewTeamConsensus.inspection(json(report), files: files).findings.map(\.id)

        #expect(Set(first).count == report.findings.count)
        #expect(Set(first).isDisjoint(with: Set(second)))
        #expect((first + second).allSatisfy { id in
            id.hasPrefix("candidate-") && UUID(uuidString: String(id.dropFirst("candidate-".count))) != nil
        })
    }

    @Test
    func `canonicalization requires an exact partition and a mapped anchor`() throws {
        let candidates = [candidate(id: "a"), candidate(id: "b")]
        let valid = ReviewCanonicalReport(findings: [finding(sources: ["a", "b"])])
        #expect(try ReviewTeamConsensus.canonical(json(valid), candidates: candidates) == valid)
        for sources in [["a"], ["a", "a"], ["a", "invented"]] {
            #expect(throws: ReviewTeamError.self) {
                try ReviewTeamConsensus.canonical(json(ReviewCanonicalReport(findings: [finding(sources: sources)])), candidates: candidates)
            }
        }
        #expect(throws: ReviewTeamError.self) {
            try ReviewTeamConsensus.canonical(json(ReviewCanonicalReport(findings: [finding(sources: ["a", "b"], line: 99)])), candidates: candidates)
        }
    }

    @Test
    func `votes cannot impersonate reviewers or omit findings`() throws {
        let report = ReviewVoteReport(votes: [vote(priority: 2)])
        let parsed = try ReviewTeamConsensus.votes(json(report), reviewerID: "real-reviewer", findings: [finding()])
        #expect(parsed.votes.first?.voterID == "real-reviewer")
        #expect(throws: ReviewTeamError.self) {
            try ReviewTeamConsensus.votes("{\"votes\":[]}", reviewerID: "lead", findings: [finding()])
        }
        #expect(throws: ReviewTeamError.self) {
            try ReviewTeamConsensus.votes(json(ReviewVoteReport(votes: [vote(priority: nil)])), reviewerID: "lead", findings: [finding()])
        }
        #expect(throws: ReviewTeamError.self) {
            try ReviewTeamConsensus.votes(
                json(ReviewVoteReport(votes: [vote(priority: 1, rationale: "\t")])),
                reviewerID: "lead",
                findings: [finding()]
            )
        }
    }

    @Test
    func `priority uses the majority supported severity`() throws {
        let team = reviewTestTeam(count: 3)
        let reports = Dictionary(uniqueKeysWithValues: zip(team, [0, 2, 2]).map { member, priority in
            (member.id, ReviewVoteReport(votes: [vote(priority: priority)]))
        })
        let result = try ReviewTeamConsensus.accepted(findings: [finding()], reports: reports, team: team)
        #expect(result.first?.priority == 2)
    }

    @Test
    func `failures and abstentions never shrink the denominator`() throws {
        let team = reviewTestTeam(count: 5)
        let reports = [
            team[0].id: ReviewVoteReport(votes: [vote(priority: 1)]),
            team[1].id: ReviewVoteReport(votes: [vote(priority: 1)]),
            team[2].id: ReviewVoteReport(votes: [vote(priority: nil, decision: .abstain)])
        ]
        #expect(try ReviewTeamConsensus.accepted(findings: [finding()], reports: reports, team: team).isEmpty)
        #expect(throws: ReviewTeamError.quorumRequired(3)) {
            try ReviewTeamConsensus.accepted(findings: [finding()], reports: reports.filter { $0.key != team[2].id }, team: team)
        }
    }

    private var files: [DiffFile] { DiffParser.parse(makeUnifiedDiffFixture(fileCount: 1)) }

    private func candidate(id: String = "untrusted", line: Int = 1, evidence: String = "The guard is absent.") -> ReviewCandidate {
        ReviewCandidate(id: id, priority: 2, path: "File0.swift", line: line, side: "RIGHT",
                        body: "A concrete problem.", evidence: evidence)
    }

    private func finding(sources: [String] = ["a"], line: Int = 1) -> ReviewCanonicalFinding {
        ReviewCanonicalFinding(id: "finding", sourceCandidateIDs: sources, path: "File0.swift", line: line,
                               side: "RIGHT", body: "A concrete problem.")
    }

    private func vote(
        priority: Int?,
        decision: ReviewTeamVote.Decision = .agree,
        rationale: String = "Checked the guard."
    ) -> ReviewTeamVote {
        ReviewTeamVote(voterID: "untrusted", findingID: "finding", decision: decision, priority: priority, rationale: rationale)
    }

    private func json<T: Encodable>(_ value: T) throws -> String {
        try ReviewTeamDigest.jsonString(value)
    }
}

func reviewTestTeam(count: Int = 3) -> [ReviewWorkerConfiguration] {
    (0..<count).map { index in
        ReviewWorkerConfiguration(id: index == 0 ? "lead" : "peer-\(index)", providerID: "codex",
                                  modelOptionID: "model-\(index)", launchModel: "model-\(index)",
                                  effort: "medium", executablePath: "/fake/codex")
    }
}
