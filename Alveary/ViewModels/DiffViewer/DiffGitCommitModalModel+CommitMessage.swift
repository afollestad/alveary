import Foundation

/// Commit-message generation: resolving what to commit with, and assembling the
/// status-and-diff context the generation prompt is built from.
extension DiffGitCommitModalModel {
    /// Returns the typed message, or generates one when the field is blank.
    func resolvedCommitMessage() async throws -> String {
        let trimmedMessage = commitMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedMessage.isEmpty else {
            return trimmedMessage
        }

        phase = .generating
        let context = try await commitMessageGenerationContext()
        let prompt = CommitMessageGenerationPromptBuilder.build(
            editablePrompt: settingsService.current.commitMessageGenerationPrompt,
            includeUnstagedChanges: includeUnstagedChanges,
            context: context
        )
        let generatedMessage = try await generateCommitMessage(prompt)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !generatedMessage.isEmpty else {
            throw DiffGitCommitModalError.message("Commit message generation returned no message.")
        }
        commitMessage = generatedMessage
        return generatedMessage
    }

    func commitMessageGenerationContext() async throws -> String {
        let statuses = try await gitService.status(in: context.directory)
        var sections: [String] = []

        sections.append(changedFilesSection(statuses))

        let stagedPaths = DiffViewerPathSupport.uniquePaths(statuses.filter(\.isStaged).map(\.path))
        if !stagedPaths.isEmpty {
            sections.append(await diffSection(title: "Staged Diff", paths: stagedPaths, scope: .staged))
        }

        if includeUnstagedChanges {
            let trackedUnstagedPaths = DiffViewerPathSupport.uniquePaths(
                statuses
                    .filter { !$0.isStaged && $0.status != .untracked }
                    .map(\.path)
            )
            if !trackedUnstagedPaths.isEmpty {
                sections.append(await diffSection(title: "Unstaged Diff", paths: trackedUnstagedPaths, scope: .unstaged))
            }

            for status in statuses where !status.isStaged && status.status == .untracked {
                sections.append(await untrackedDiffSection(path: status.path))
            }
        }

        return sections
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
}

private extension DiffGitCommitModalModel {
    func changedFilesSection(_ statuses: [FileStatus]) -> String {
        let rows = statuses.map { status in
            let stagedText = status.isStaged ? "staged" : "unstaged"
            return "- \(status.path) (\(stagedText), \(status.status.rawValue))"
        }
        return """
        ## Changed Files
        \(rows.isEmpty ? "- No changed files reported." : rows.joined(separator: "\n"))
        """
    }

    func diffSection(title: String, paths: [String], scope: DiffScope) async -> String {
        do {
            let diff = try await gitService.diff(paths: paths, scope: scope, in: context.directory)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !diff.isEmpty else {
                return """
                ## \(title)
                No diff text was reported for \(paths.joined(separator: ", ")).
                """
            }
            return """
            ## \(title)
            ```diff
            \(diff)
            ```
            """
        } catch {
            return """
            ## \(title)
            Diff unavailable for \(paths.joined(separator: ", ")): \(error.localizedDescription)
            """
        }
    }

    func untrackedDiffSection(path: String) async -> String {
        do {
            let diff = try await gitService.syntheticAddedDiff(for: path, in: context.directory)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard !diff.isEmpty else {
                return """
                ## Untracked File
                No diff text was reported for \(path).
                """
            }
            return """
            ## Untracked File
            ```diff
            \(diff)
            ```
            """
        } catch {
            return """
            ## Untracked File
            Diff unavailable for \(path): \(error.localizedDescription)
            """
        }
    }
}
