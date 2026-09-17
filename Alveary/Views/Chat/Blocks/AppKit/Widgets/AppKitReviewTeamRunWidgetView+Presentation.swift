import AgentCLIKit
import Foundation

/// Keeps the transcript concise while the run details retain the full workflow explanations.
enum ReviewTeamRunCardPresentation {
    /// Match exact catalog IDs only: resolving a saved family alias would attribute it to today's pinned version.
    static func modelLabel(harnessID: String, modelOptionID: String) -> String {
        if let harnessID = AgentHarnessID(rawValue: harnessID),
           let option = AgentDefaultModelOptions.staticOptions(for: harnessID).first(where: {
               $0.id == modelOptionID || $0.model == modelOptionID
           }) {
            return option.label
        }
        return modelOptionID.split(separator: "-").map { word in
            let normalized = word.lowercased()
            if normalized == "gpt" { return "GPT" }
            if normalized.first == "o", normalized.count > 1, normalized.dropFirst().allSatisfy(\.isNumber) {
                return normalized
            }
            return word.capitalized
        }.joined(separator: " ")
    }

    static func pauseExplanation(_ run: ReviewTeamRun) -> String? {
        if run.phase == .waitingForGitHub { return run.gitHubWait?.limit.waitingMessage }
        guard run.phase == .awaitingDecision, let phase = run.pausedPhase else { return nil }
        let next = phase == .inspecting
            ? "consolidate and cross-check findings"
            : "prepare a proposal from completed votes"
        let action = run.canContinueWithMajority
            ? "Retry failed reviewers or continue to \(next)."
            : "Retry failed reviewers to continue. Next: \(next)."
        return "\(action) Fixed majority: \(run.requiredVotes)/\(run.team.count) required. Nothing is submitted automatically."
    }

    static func partialCompletionWarning(_ run: ReviewTeamRun) -> String? {
        guard run.partialCompletionWarning != nil else { return nil }
        var incomplete: [String] = []
        if run.inspections.count < run.team.count {
            incomplete.append("\(run.inspections.count)/\(run.team.count) inspected")
        }
        if run.canonical?.findings.isEmpty == false, run.voteReports.count < run.team.count {
            incomplete.append("\(run.voteReports.count)/\(run.team.count) cross-checked")
        }
        return "Partial team review: \(incomplete.joined(separator: " · ")). Fixed majority: \(run.requiredVotes)/\(run.team.count) required."
    }
}
