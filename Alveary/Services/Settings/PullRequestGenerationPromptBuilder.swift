import Foundation

/// One commit's contribution to the generation context. Callers fetch diffs only
/// for the first `PullRequestGenerationPromptBuilder.maxCommits` commits; the
/// builder bounds the text again so a huge branch cannot blow up the prompt.
struct PullRequestGenerationCommit {
    let subject: String
    let diff: String
}

enum PullRequestGenerationPromptBuilder {
    /// Callers stop fetching per-commit diffs past this count; subjects beyond
    /// it still list so the prompt names the whole branch.
    static let maxCommits = 20
    /// Total diff characters across all commits; per-commit slices shrink as the
    /// budget runs out.
    static let maxTotalDiffCharacters = 60_000

    static func build(editablePrompt: String, context: String) -> String {
        [
            editablePrompt.trimmingCharacters(in: .whitespacesAndNewlines),
            context.trimmingCharacters(in: .whitespacesAndNewlines)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: "\n\n")
    }

    static func context(
        baseBranch: String,
        headBranch: String,
        commitSubjects: [String],
        commits: [PullRequestGenerationCommit]
    ) -> String {
        var sections: [String] = []
        sections.append("## Branch\n`\(headBranch)` into `\(baseBranch)`")

        let subjectRows = commitSubjects.map { "- \($0)" }
        sections.append("""
        ## Commits
        \(subjectRows.isEmpty ? "- No commits reported." : subjectRows.joined(separator: "\n"))
        """)

        var remainingBudget = maxTotalDiffCharacters
        for commit in commits.prefix(maxCommits) where remainingBudget > 0 {
            let slice = String(commit.diff.prefix(remainingBudget))
            remainingBudget -= slice.count
            guard !slice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                continue
            }
            let truncationNote = slice.count < commit.diff.count ? "\n[diff truncated]" : ""
            sections.append("""
            ## \(commit.subject)
            ```diff
            \(slice)
            ```\(truncationNote)
            """)
        }

        return sections.joined(separator: "\n\n")
    }

    /// The response contract: the first non-empty line is the title (a leading
    /// markdown heading marker is tolerated and stripped), the remainder is the
    /// markdown body. Returns nil when no title line exists at all.
    static func parseResponse(_ text: String) -> (title: String, body: String)? {
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard let titleIndex = lines.firstIndex(where: {
            !$0.trimmingCharacters(in: .whitespaces).isEmpty
        }) else {
            return nil
        }
        var title = lines[titleIndex].trimmingCharacters(in: .whitespaces)
        while title.hasPrefix("#") {
            title.removeFirst()
        }
        title = title.trimmingCharacters(in: .whitespaces)
        guard !title.isEmpty else {
            return nil
        }
        let body = lines[(titleIndex + 1)...]
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (title, body)
    }
}
