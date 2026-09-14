import Foundation

/// Validation and voting never depend on a model's claimed count, author identity, or final verdict.
enum ReviewTeamConsensus {
    static let maximumFindings = 100
    static let maximumOutputBytes = 2 * 1024 * 1024

    static func requiredVotes(teamSize: Int) -> Int { teamSize / 2 + 1 }

    /// Normalize framing only during validation so execution history retains the exact provider response.
    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard text.utf8.count <= maximumOutputBytes else {
            throw ReviewTeamError.invalidOutput("The reviewer response exceeded the size limit.")
        }
        let data = Data(normalizedJSON(text).utf8)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch let error as DecodingError {
            throw ReviewTeamError.invalidOutput(decodingDiagnostic(error, data: data))
        } catch {
            throw ReviewTeamError.invalidOutput("The reviewer response does not match the requested schema.")
        }
    }

    static func inspection(_ text: String, files: [DiffFile]) throws -> ReviewInspectionReport {
        let report = try decode(ReviewInspectionReport.self, from: text)
        guard report.findings.count <= maximumFindings else {
            throw ReviewTeamError.invalidOutput("Too many findings in one inspection.")
        }
        let findings = try report.findings.map { finding in
            guard (0...3).contains(finding.priority), validBody(finding.body),
                  !finding.evidence.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  finding.evidence.count <= 4000 else {
                throw ReviewTeamError.invalidOutput("Findings need priority 0–3, a bounded comment, and supporting evidence.")
            }
            try validateAnchor(path: finding.path, line: finding.line, side: finding.side, files: files)
            var assigned = finding
            assigned.id = "candidate-\(UUID().uuidString.lowercased())"
            return assigned
        }
        return ReviewInspectionReport(findings: findings)
    }

    static func canonical(_ text: String, candidates: [ReviewCandidate]) throws -> ReviewCanonicalReport {
        let report = try decode(ReviewCanonicalReport.self, from: text)
        let mapped = report.findings.flatMap(\.sourceCandidateIDs)
        guard mapped.count == candidates.count, Set(mapped) == Set(candidates.map(\.id)),
              Set(report.findings.map(\.id)).count == report.findings.count else {
            throw ReviewTeamError.invalidOutput("Canonical findings must map every source candidate exactly once, with unique finding IDs.")
        }
        for finding in report.findings {
            guard !finding.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  finding.id.count <= 100, validBody(finding.body), !finding.sourceCandidateIDs.isEmpty,
                  candidates.contains(where: {
                      finding.sourceCandidateIDs.contains($0.id) && $0.path == finding.path &&
                          $0.line == finding.line && $0.side == finding.side
                  }) else {
                throw ReviewTeamError.invalidOutput("Each canonical anchor must come from a mapped source candidate.")
            }
        }
        return report
    }

    static func votes(_ text: String, reviewerID: String, findings: [ReviewCanonicalFinding]) throws -> ReviewVoteReport {
        let report = try decode(ReviewVoteReport.self, from: text)
        guard report.votes.count == findings.count,
              Set(report.votes.map(\.findingID)) == Set(findings.map(\.id)) else {
            throw ReviewTeamError.invalidOutput("Return exactly one vote for each canonical finding.")
        }
        let votes = try report.votes.map { vote in
            guard !vote.rationale.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  vote.rationale.count <= 2000,
                  vote.decision != .agree || vote.priority.map({ (0...3).contains($0) }) == true else {
                throw ReviewTeamError.invalidOutput("Votes need a short rationale; agreement also requires priority 0–3.")
            }
            return ReviewTeamVote(
                voterID: reviewerID, findingID: vote.findingID, decision: vote.decision,
                priority: vote.decision == .agree ? vote.priority : nil, rationale: vote.rationale
            )
        }
        return ReviewVoteReport(votes: votes)
    }

    static func accepted(
        findings: [ReviewCanonicalFinding], reports: [String: ReviewVoteReport], team: [ReviewWorkerConfiguration]
    ) throws -> [ReviewAcceptedFinding] {
        let required = requiredVotes(teamSize: team.count)
        let memberIDs = Set(team.map(\.id))
        let validReports = reports.filter { memberIDs.contains($0.key) }
        guard validReports.count >= required else { throw ReviewTeamError.quorumRequired(required) }
        return findings.compactMap { finding in
            let votes = team.compactMap { validReports[$0.id]?.votes.first(where: { $0.findingID == finding.id }) }
            let priorities = votes.filter { $0.decision == .agree }.compactMap(\.priority).sorted()
            guard priorities.count >= required else { return nil }
            return ReviewAcceptedFinding(finding: finding, priority: priorities[required - 1], votes: votes)
        }
    }

    /// Unwrap only a complete outer JSON fence; searching prose for an object could select the wrong report.
    private static func normalizedJSON(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let openingEnd = trimmed.firstIndex(where: \.isNewline),
              let closingStart = trimmed.lastIndex(where: \.isNewline),
              openingEnd < closingStart else { return trimmed }
        let opening = trimmed[..<openingEnd].trimmingCharacters(in: .whitespaces).lowercased()
        let closing = trimmed[trimmed.index(after: closingStart)...].trimmingCharacters(in: .whitespaces)
        guard opening == "```json" || opening == "```", closing == "```" else { return trimmed }
        return String(trimmed[trimmed.index(after: openingEnd)..<closingStart])
    }

    /// Decoder debug descriptions can echo response content; expose only the failure category and schema path.
    private static func decodingDiagnostic(_ error: DecodingError, data: Data) -> String {
        switch error {
        case .keyNotFound(let key, let context):
            return "Missing required field at \(codingPath(context.codingPath + [key]))."
        case .valueNotFound(_, let context):
            return "Required value is null at \(codingPath(context.codingPath))."
        case .typeMismatch(_, let context):
            return "Incorrect value type at \(codingPath(context.codingPath))."
        case .dataCorrupted(let context):
            // Foundation also loses the path for numeric conversion failures, which can still be valid JSON.
            if context.codingPath.isEmpty,
               (try? JSONSerialization.jsonObject(with: data, options: .fragmentsAllowed)) == nil {
                return "The reviewer response is not valid JSON."
            }
            return "Invalid value at \(codingPath(context.codingPath))."
        @unknown default:
            return "The reviewer response does not match the requested schema."
        }
    }

    private static func codingPath(_ keys: [any CodingKey]) -> String {
        keys.reduce("$") { path, key in
            if let index = key.intValue { return "\(path)[\(index)]" }
            return "\(path).\(key.stringValue)"
        }
    }

    private static func validBody(_ body: String) -> Bool {
        !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && body.count <= 6000 &&
            body.range(of: #"^\s*(\*\*)?\[P[0-3]\]"#, options: .regularExpression) == nil
    }

    private static func validateAnchor(path: String, line: Int, side: String, files: [DiffFile]) throws {
        guard let parsedSide = DiffCommentAnchor.Side(rawValue: side), line > 0 else {
            throw ReviewTeamError.invalidOutput("Use a positive diff line and LEFT or RIGHT side.")
        }
        let target = DiffCommentAnchor(path: path, side: parsedSide, line: line)
        guard files.contains(where: { file in
            file.path == path && file.hunks.contains { hunk in
                hunk.lines.contains { FlattenedDiffPreviewRows.commentAnchor(for: $0, path: path) == target }
            }
        }) else { throw ReviewTeamError.invalidOutput("The finding's anchor is not present in the reviewed diff.") }
    }
}
