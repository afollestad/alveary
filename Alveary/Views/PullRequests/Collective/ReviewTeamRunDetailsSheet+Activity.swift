import SwiftUI

struct ReviewTeamRunActivity: View {
    let run: ReviewTeamRun
    let store: ReviewTeamHistoryStore?
    @Binding var reviewerID: String

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Picker("Reviewer", selection: $reviewerID) {
                Text("All reviewers").tag("all")
                ForEach(run.team) { member in
                    Text(ReviewTeamRunPresentation.role(member, in: run)).tag(member.id)
                }
            }
            if run.history == nil || run.historyIsPartial == true {
                Text("Earlier attempts were not recorded. Validated results and any newly recorded attempts are shown below.")
                    .foregroundStyle(.secondary)
            } else {
                Text("""
                    Prompts are available when an attempt starts; final responses appear when it finishes. \
                    Invalid responses and retries remain in the history.
                    """)
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(run.team.filter { reviewerID == "all" || $0.id == reviewerID }) { member in
                ReviewTeamReviewerActivity(run: run, member: member, store: store)
            }
        }
    }
}

private struct ReviewTeamReviewerActivity: View {
    let run: ReviewTeamRun
    let member: ReviewWorkerConfiguration
    let store: ReviewTeamHistoryStore?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(ReviewTeamRunPresentation.role(member, in: run)).font(.headline)
            Text("Requested: \(ReviewTeamRunPresentation.requestedModel(member))")
                .font(.callout).foregroundStyle(.secondary)
            if let report = run.inspections[member.id] {
                DisclosureGroup("Validated inspection · \(report.findings.count) findings") {
                    ForEach(report.findings) { finding in
                        ReviewTeamCandidateDetail(candidate: finding)
                            .padding(.vertical, 8)
                    }
                    if report.findings.isEmpty { Text("No findings returned.").padding(.top, 8) }
                }
            }
            let attempts = (run.history ?? []).filter { $0.reviewerID == member.id }
            ForEach(Array(attempts.enumerated()), id: \.element.id) { index, attempt in
                ReviewTeamAttemptDetail(run: run, attempt: attempt, number: index + 1, store: store)
            }
            if attempts.isEmpty, run.history != nil {
                Text("No recorded attempts yet.").foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct ReviewTeamAttemptDetail: View {
    let run: ReviewTeamRun
    let attempt: ReviewTeamAttempt
    let number: Int
    let store: ReviewTeamHistoryStore?

    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Text("Generation \(attempt.generation + 1) · \(attempt.startedAt.formatted(date: .abbreviated, time: .standard))")
                    .font(.caption).foregroundStyle(.secondary)
                if let finishedAt = attempt.finishedAt {
                    Text("Duration: \(Int(max(0, finishedAt.timeIntervalSince(attempt.startedAt)))) seconds")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if let error = attempt.error { Text(error).foregroundStyle(.red) }
                ReviewTeamHistoryArtifactView(title: "Exact app prompt", artifact: attempt.prompt, run: run, store: store)
                if let response = attempt.response {
                    ReviewTeamHistoryArtifactView(title: "Final response", artifact: response, run: run, store: store)
                } else {
                    Text(attempt.status == .running ? "Waiting for final response…" : "No final response retained.")
                        .foregroundStyle(.secondary)
                }
                DisclosureGroup("Input packet · \(attempt.inputs.count) files") {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(attempt.packetHash).font(.system(.caption, design: .monospaced))
                        ForEach(attempt.inputs, id: \.name) { artifact in
                            ReviewTeamHistoryArtifactView(title: artifact.name, artifact: artifact, run: run, store: store)
                        }
                    }.padding(.top, 8)
                }
            }.padding(.vertical, 10)
        } label: {
            HStack {
                Text("\(attempt.phase.title) · Attempt \(number)")
                Spacer()
                Text(attempt.status.rawValue.capitalized).font(.callout.weight(.medium))
            }
            .accessibilityElement(children: .combine)
        }
    }
}

struct ReviewTeamCandidateDetail: View {
    let candidate: ReviewCandidate

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("P\(candidate.priority) · \(candidate.path):\(candidate.line) · \(candidate.side)")
                .font(.system(.caption, design: .monospaced)).foregroundStyle(.secondary)
            AppMarkdownInlineParagraph(text: candidate.body)
            Text("Supporting evidence").font(.caption.weight(.semibold))
            AppMarkdownInlineParagraph(text: candidate.evidence, textStyle: .callout)
        }
    }
}
