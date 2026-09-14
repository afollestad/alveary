import Foundation
import Testing

@testable import Alveary

struct ReviewTeamConsensusTests {
    @Test(arguments: [2, 3, 4, 5])
    func `quorum is always the configured majority`(count: Int) {
        #expect(ReviewTeamConsensus.requiredVotes(teamSize: count) == count / 2 + 1)
    }

    @Test
    func `inspection requires exact anchors and nonempty evidence`() throws {
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

        #expect(first.count == 2)
        #expect(second.count == 2)
        #expect(Set(first).count == 2)
        #expect(Set(second).count == 2)
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

    @Test(arguments: ["bare", "", "json", "JSON"])
    func `all review reports accept a single JSON response with optional code fencing`(format: String) throws {
        func response(_ payload: String) -> String {
            if format == "bare" { return " \t\r\n" + payload + "\r\n\t " }
            return " \t\r\n  ```\(format) \t\r\n\(payload)\r\n \t```  \r\n\t "
        }
        let evidence = #"The value "雪" retains literal ``` backticks and a \ path."#
        let inspection = try ReviewTeamConsensus.inspection(
            response(json(ReviewInspectionReport(findings: [candidate(evidence: evidence)]))), files: files
        )
        #expect(inspection.findings.count == 1)
        #expect(inspection.findings.first?.evidence == evidence)
        let canonical = ReviewCanonicalReport(findings: [finding()])
        #expect(try ReviewTeamConsensus.canonical(response(json(canonical)), candidates: [candidate(id: "a")]) == canonical)
        let votes = try ReviewTeamConsensus.votes(
            response(json(ReviewVoteReport(votes: [vote(priority: 2)]))), reviewerID: "trusted", findings: canonical.findings
        )
        #expect(votes.votes.first?.voterID == "trusted")
        #expect(votes.votes.first?.priority == 2)
    }

    @Test(arguments: [
        "Here is the result:\n{\"findings\":[]}",
        "{\"findings\":[]}\nDone.",
        "```json\n{\"findings\":[]}",
        "```json {\"findings\":[]}\n```",
        "```json\n{\"findings\":[]}```",
        "```json\n{\"findings\":[]}\n```\n```json\n{\"findings\":[]}\n```",
        "{\"findings\":[]}\n{\"findings\":[]}",
        "```json\n{\"findings\":[]}\n{\"findings\":[]}\n```",
        "```javascript\n{\"findings\":[]}\n```",
        "```json\n{\"findings\":[]}\n```\nDone.",
        "```json\n{\"findings\": [}\n```"
    ])
    func `decoding rejects prose incomplete fences and ambiguous or malformed payloads`(text: String) {
        #expect(throws: ReviewTeamError.invalidOutput("The reviewer response is not valid JSON.")) {
            try ReviewTeamConsensus.inspection(text, files: files)
        }
    }

    @Test(arguments: [
        (
            #"{"findings":[{"id":"a","priority":2,"path":"File0.swift","line":1,"side":"RIGHT","body":"Problem"}]}"#,
            "Missing required field at $.findings[0].evidence."
        ),
        (
            #"{"findings":[{"id":"a","priority":2,"path":"File0.swift","line":1,"side":"RIGHT","body":"Problem","evidence":null}]}"#,
            "Required value is null at $.findings[0].evidence."
        ),
        (
            #"{"findings":[{"id":"a","priority":"2","path":"File0.swift","line":1,"side":"RIGHT","body":"Problem","evidence":"Guard"}]}"#,
            "Incorrect value type at $.findings[0].priority."
        ),
        ("[]", "Incorrect value type at $."),
        (
            #"{"findings":[{"id":"a","priority":2.5,"path":"File0.swift","line":1,"side":"RIGHT","body":"Problem","evidence":"Guard"}]}"#,
            "Invalid value at $."
        )
    ])
    func `schema diagnostics identify the failing field and array position`(text: String, diagnostic: String) {
        #expect(throws: ReviewTeamError.invalidOutput(diagnostic)) {
            try ReviewTeamConsensus.inspection(text, files: files)
        }
    }

    @Test
    func `invalid vote decisions identify the failing field`() {
        let text = #"{"votes":[{"voterID":"a","findingID":"finding","decision":"approve","priority":1,"rationale":"Checked"}]}"#
        #expect(throws: ReviewTeamError.invalidOutput("Invalid value at $.votes[0].decision.")) {
            try ReviewTeamConsensus.votes(text, reviewerID: "trusted", findings: [finding()])
        }
    }

    @Test
    func `fenced findings still require a valid diff anchor`() throws {
        let payload = try json(ReviewInspectionReport(findings: [candidate(line: 99)]))
        #expect(throws: ReviewTeamError.invalidOutput("The finding's anchor is not present in the reviewed diff.")) {
            try ReviewTeamConsensus.inspection("```json\n\(payload)\n```", files: files)
        }
    }

    @Test(arguments: [" ", "\u{2003}"])
    func `response size is bounded in original UTF8 bytes before removing whitespace or fences`(padding: String) {
        let text = String(repeating: padding, count: ReviewTeamConsensus.maximumOutputBytes / padding.utf8.count)
            + "```json\n{\"findings\":[]}\n```"
        #expect(throws: ReviewTeamError.invalidOutput("The reviewer response exceeded the size limit.")) {
            try ReviewTeamConsensus.inspection(text, files: files)
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
