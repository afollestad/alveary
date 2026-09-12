import SwiftUI

struct ReviewTeamRunDecisions: View {
    let run: ReviewTeamRun

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("""
                The lead merges candidates; it cannot invent findings. Everyone votes on the same frozen wording and anchor. \
                The final priority is the most severe level supported by \(run.requiredVotes) reviewers.
                """)
                .font(.callout).foregroundStyle(.secondary)
            if let canonical = run.canonical, !canonical.findings.isEmpty {
                ForEach(canonical.findings) { finding in
                    ReviewTeamCanonicalDecision(run: run, finding: finding)
                }
            } else if [.staging, .staged, .completed].contains(run.phase), run.inspections.count >= run.requiredVotes,
                      run.inspections.values.allSatisfy({ $0.findings.isEmpty }) {
                Text("The completed inspections returned no candidates. Consolidation and voting are not needed.")
            } else {
                Text("Canonical findings will appear after the lead consolidates the independent inspections.")
                    .foregroundStyle(.secondary)
            }
            Text("Agreement selects new findings; staging still checks anchors and existing comments. Nothing is submitted automatically.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct ReviewTeamCanonicalDecision: View {
    let run: ReviewTeamRun
    let finding: ReviewCanonicalFinding

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ReviewTeamRunPresentation.decision(finding, in: run)).font(.headline)
            Text("\(finding.path):\(finding.line) · \(finding.side)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            AppMarkdownInlineParagraph(text: finding.body)
            DisclosureGroup("Consolidated from \(finding.sourceCandidateIDs.count) candidates") {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(run.team) { member in
                        ForEach(sources(member)) { candidate in
                            VStack(alignment: .leading, spacing: 6) {
                                Text("\(ReviewTeamRunPresentation.role(member, in: run)) · \(candidate.id)")
                                    .font(.caption.weight(.semibold))
                                ReviewTeamCandidateDetail(candidate: candidate)
                            }
                        }
                    }
                }.padding(.top, 8)
            }
            Divider()
            ForEach(run.team) { member in
                ReviewTeamDecisionVote(run: run, finding: finding, member: member)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private func sources(_ member: ReviewWorkerConfiguration) -> [ReviewCandidate] {
        (run.inspections[member.id]?.findings ?? []).filter { finding.sourceCandidateIDs.contains($0.id) }
    }
}

private struct ReviewTeamDecisionVote: View {
    let run: ReviewTeamRun
    let finding: ReviewCanonicalFinding
    let member: ReviewWorkerConfiguration

    var body: some View {
        let vote = run.voteReports[member.id]?.votes.first { $0.findingID == finding.id }
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(ReviewTeamRunPresentation.role(member, in: run)).fontWeight(.semibold)
                Spacer()
                Text(vote.map(decisionLabel) ?? missingVoteLabel)
                    .font(.callout.weight(.semibold))
            }
            if let vote {
                AppMarkdownInlineParagraph(text: vote.rationale, textStyle: .callout)
            } else if let failure = run.failures["crossChecking:\(member.id)"] {
                Text(failure).font(.callout).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var missingVoteLabel: String {
        if run.failures["crossChecking:\(member.id)"] != nil { return "Failed · No valid vote" }
        return run.phase.isWorking ? "Awaiting vote" : "No valid vote"
    }

    private func decisionLabel(_ vote: ReviewTeamVote) -> String {
        switch vote.decision {
        case .agree: "Agree" + (vote.priority.map { " · P\($0)" } ?? "")
        case .disagree: "Disagree"
        case .abstain: "Abstain"
        }
    }
}
