import SwiftUI

/// Reads the coordinator while open, but keeps an older transcript run pinned when a new review starts.
struct ReviewTeamRunDetailsSheet: View {
    let initialRun: ReviewTeamRun
    var coordinator: PullRequestReviewTeamCoordinator?
    var initialReviewerID: String?
    let onClose: () -> Void

    @State private var tab = ReviewTeamDetailsTab.overview
    @State private var reviewerID = "all"

    var body: some View {
        let run = currentRun
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Review run").font(.title2.weight(.semibold))
                    Text(run.phase.title).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done", action: onClose)
                    .secondaryActionButtonStyle()
                    .keyboardShortcut(.cancelAction)
            }
            Picker("Run details", selection: $tab) {
                ForEach(ReviewTeamDetailsTab.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch tab {
                    case .overview:
                        ReviewTeamRunOverview(run: run)
                    case .activity:
                        ReviewTeamRunActivity(
                            run: run, store: coordinator?.historyStore, reviewerID: $reviewerID
                        )
                    case .decisions:
                        ReviewTeamRunDecisions(run: run)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(2)
                .textSelection(.enabled)
            }
            if run.phase == .awaitingDecision {
                pausedActions(run)
            }
        }
        .padding(24)
        .frame(width: 780, height: 690)
        .onAppear {
            if let initialReviewerID {
                reviewerID = initialReviewerID
                tab = .activity
            }
        }
    }

    private var currentRun: ReviewTeamRun {
        guard let live = coordinator?.runs[initialRun.conversationID], live.id == initialRun.id else { return initialRun }
        return live
    }

    private func pausedActions(_ run: ReviewTeamRun) -> some View {
        HStack {
            Button("Cancel review") { post(.reviewTeamCancelRequested, run: run) }
                .secondaryActionButtonStyle()
            Spacer()
            if run.canRetryFailedReviewers {
                Button("Retry failed reviewers") { post(.reviewTeamRetryFailedRequested, run: run) }
                    .secondaryActionButtonStyle()
            }
            if run.canContinueWithMajority {
                Button("Continue with majority") { post(.reviewTeamContinueRequested, run: run) }
                    .primaryActionButtonStyle()
            }
        }
    }

    private func post(_ name: Notification.Name, run: ReviewTeamRun) {
        NotificationCenter.default.post(name: name, object: nil, userInfo: [
            "conversationID": run.conversationID, "runID": run.id, "generation": run.generation
        ])
    }
}

enum ReviewTeamDetailsTab: String, CaseIterable, Identifiable {
    case overview = "Overview", activity = "Reviewer activity", decisions = "Decisions"
    var id: String { rawValue }
}

enum ReviewTeamRunPresentation {
    struct ReviewerStatus {
        let label: String
        let detail: String?
        let failed: Bool
    }

    static func role(_ member: ReviewWorkerConfiguration, in run: ReviewTeamRun) -> String {
        guard member.id != "lead" else { return "Lead reviewer" }
        return "Peer reviewer \(run.team.firstIndex(where: { $0.id == member.id }) ?? 1)"
    }

    static func requestedModel(_ member: ReviewWorkerConfiguration) -> String {
        "\(member.providerID) · \(member.launchModel) · \(member.effort)"
    }

    static func decision(_ finding: ReviewCanonicalFinding, in run: ReviewTeamRun) -> String {
        let count = run.team.filter { member in
            run.voteReports[member.id]?.votes.contains { $0.findingID == finding.id && $0.decision == .agree } == true
        }.count
        let agreement = "\(count)/\(run.team.count) agreed"
        if let accepted = run.accepted.first(where: { $0.finding.id == finding.id }) {
            return "\(agreement) · Majority priority P\(accepted.priority)"
        }
        if run.phase.isWorking || run.phase == .awaitingDecision { return "\(agreement) · Decision pending" }
        if run.voteReports.count < run.requiredVotes { return "Not proposed · Insufficient complete cross-checks" }
        return "Not proposed · \(agreement), \(run.requiredVotes) required"
    }

    static func pauseExplanation(_ run: ReviewTeamRun) -> String? {
        guard run.phase == .awaitingDecision, let phase = run.pausedPhase else { return nil }
        let count = run.completedReviewerIDs(in: phase).count
        let step = phase == .inspecting ? "inspections" : "cross-checks"
        let next = phase == .inspecting
            ? "Continuing uses these inspections, then consolidates and cross-checks any findings before preparing a proposal."
            : "Continuing prepares a proposal from the completed votes, using the unchanged majority requirement."
        return "\(count)/\(run.team.count) \(step) completed; the remaining reviewers failed. "
            + "Retry them or continue with the available majority. \(next) Nothing is submitted automatically."
    }

    static func status(for member: ReviewWorkerConfiguration, in run: ReviewTeamRun) -> ReviewerStatus {
        let phase = run.phase == .awaitingDecision ? run.pausedPhase : run.phase
        let currentFailure = phase.flatMap { run.failures["\($0.rawValue):\(member.id)"] }
        let earlierFailure = run.failures.sorted(by: { $0.key < $1.key }).first {
            $0.key == member.id || $0.key.hasSuffix(":\(member.id)")
        }
        let failure = currentFailure ?? earlierFailure?.value
        if run.voteReports[member.id] != nil {
            let prefix = currentFailure == nil && earlierFailure?.key.hasPrefix("inspecting:") == true
                ? "Earlier inspection failed" : "Earlier reviewer attempt failed"
            let detail = failure.map { "\(prefix): \(String($0.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240)))" }
            return ReviewerStatus(label: "Cross-checked", detail: detail, failed: false)
        }
        if let failure {
            let message = failure.trimmingCharacters(in: .whitespacesAndNewlines)
            return ReviewerStatus(label: "Failed", detail: message.isEmpty ? nil : String(message.prefix(240)), failed: true)
        }
        if phase == .crossChecking || run.canonical?.findings.isEmpty == false {
            let label = run.phase == .crossChecking ? "Cross-checking…" : "No valid cross-check"
            return ReviewerStatus(label: label, detail: nil, failed: false)
        }
        if run.inspections[member.id] != nil { return ReviewerStatus(label: "Inspection complete", detail: nil, failed: false) }
        let label = run.phase == .inspecting ? "Inspecting…" : run.phase == .awaitingDecision ? "No valid inspection" : "Waiting"
        return ReviewerStatus(label: label, detail: nil, failed: false)
    }
}

private struct ReviewTeamRunOverview: View {
    let run: ReviewTeamRun

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("\(run.team.count) reviewers · \(run.requiredVotes) votes required")
                .font(.headline)
            if let explanation = ReviewTeamRunPresentation.pauseExplanation(run) {
                Text(explanation).fontWeight(.medium)
            }
            if let warning = run.partialCompletionWarning { Text(warning).fontWeight(.medium) }
            Text("""
                Every reviewer inspects independently and votes. The lead also merges overlapping findings. \
                Failures and abstentions do not lower the majority.
                """)
            ForEach(run.team) { member in
                let status = ReviewTeamRunPresentation.status(for: member, in: run)
                VStack(alignment: .leading, spacing: 4) {
                    Text(ReviewTeamRunPresentation.role(member, in: run)).fontWeight(.semibold)
                    Text("Requested: \(ReviewTeamRunPresentation.requestedModel(member))")
                        .font(.callout).foregroundStyle(.secondary)
                    if run.phase == .awaitingDecision {
                        Text(status.label).font(.callout.weight(.medium))
                        if let detail = status.detail { Text(detail).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 6) {
                Text("Pinned inputs").font(.headline)
                Text(run.url.absoluteString).font(.callout)
                Text("Base: \(run.baseOID ?? "Not acquired")")
                Text("Head: \(run.headOID ?? "Not acquired")")
                Text("Packet: \(run.inputHash ?? "Not acquired")")
                Text("Exact files are available under each recorded attempt.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .font(.system(.caption, design: .monospaced))
            if let error = run.error {
                Text(error).foregroundStyle(.red)
            }
            if run.history == nil || run.historyIsPartial == true {
                Text("""
                    This run began before execution history was recorded. Validated results are available, \
                    but earlier prompts, responses, and packet files were not retained.
                    """)
                    .foregroundStyle(.secondary)
            }
            DisclosureGroup("Saved review criteria") {
                Text(run.criteria).font(.system(.callout, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
            }
            Text("""
                Models above are the requested launch configuration, not provider-verified attribution. \
                History records app-issued inputs and final responses, not the launch environment or private reasoning streams.
                """)
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
