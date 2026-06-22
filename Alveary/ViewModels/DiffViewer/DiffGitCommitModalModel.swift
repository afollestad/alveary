import Foundation
import Observation

struct DiffGitCommitModalContext: Identifiable, Equatable {
    let id = UUID()
    let directory: String
    let targetName: String
    let baseBranch: String
    let remoteName: String?
}

@MainActor
@Observable
final class DiffGitCommitModalModel: Identifiable {
    enum BranchSelection: Equatable {
        case base
        case new
    }

    enum OperationPhase: Equatable {
        case idle
        case checking
        case generating
        case committing
        case pushing
    }

    static let commitMessagePlaceholder = "Commit message (leave blank to generate)..."

    let id = UUID()
    let context: DiffGitCommitModalContext

    var branchSelection: BranchSelection = .base
    var newBranchName: String {
        didSet {
            if oldValue != newBranchName {
                errorMessage = nil
            }
        }
    }

    var commitMessage = ""
    var includeUnstagedChanges: Bool {
        didSet {
            guard oldValue != includeUnstagedChanges else {
                return
            }
            settingsService.update { settings in
                settings.gitCommitIncludeUnstagedChanges = includeUnstagedChanges
            }
            Task { @MainActor [weak self] in
                await self?.refreshStagedPreflight()
            }
        }
    }

    var currentBranch: String?
    var hasStagedChanges: Bool?
    var isLoadingInitialState = false
    var phase: OperationPhase = .idle
    var errorMessage: String?
    var didCommitSuccessfully = false
    var forcePushRequired = false

    private let gitService: GitService
    private let settingsService: SettingsService
    private let generateCommitMessage: @MainActor (String) async throws -> String
    private let refreshAfterMutation: @MainActor () async -> Void
    private var hasLoadedInitialState = false

    init(
        context: DiffGitCommitModalContext,
        gitService: GitService,
        settingsService: SettingsService,
        generateCommitMessage: @escaping @MainActor (String) async throws -> String,
        refreshAfterMutation: @escaping @MainActor () async -> Void
    ) {
        self.context = context
        self.gitService = gitService
        self.settingsService = settingsService
        self.generateCommitMessage = generateCommitMessage
        self.refreshAfterMutation = refreshAfterMutation
        self.includeUnstagedChanges = settingsService.current.gitCommitIncludeUnstagedChanges
        self.newBranchName = Self.defaultNewBranchName(
            branchPrefix: settingsService.current.branchPrefix,
            targetName: context.targetName
        )
    }

    var controlsDisabled: Bool {
        isLoadingInitialState || phase != .idle || didCommitSuccessfully
    }

    var commitButtonDisabled: Bool {
        didCommitSuccessfully || controlsDisabled || preflightMessage != nil
    }

    var primaryActionButtonDisabled: Bool {
        if forcePushRequired {
            return isLoadingInitialState || phase != .idle
        }
        return didCommitSuccessfully || controlsDisabled || preflightMessage != nil
    }

    var primaryActionButtonTitle: String {
        forcePushRequired ? "Force push" : "Commit and push"
    }

    var isOperationInFlight: Bool {
        phase != .idle
    }

    var selectedBranchTitle: String {
        switch branchSelection {
        case .base:
            return context.baseBranch
        case .new:
            return "New branch"
        }
    }

    var isBaseBranchSelectable: Bool {
        currentBranch == nil || currentBranch == context.baseBranch
    }

    var preflightMessage: String? {
        if branchSelection == .base,
           let currentBranch,
           currentBranch != context.baseBranch {
            return "Current branch is `\(currentBranch)`; choose New branch to commit from here."
        }

        if branchSelection == .new, trimmedNewBranchName.isEmpty {
            return "Enter a branch name."
        }

        if !includeUnstagedChanges, hasStagedChanges == false {
            return "No staged changes to commit."
        }

        return nil
    }

    var statusMessage: String? {
        if isLoadingInitialState {
            return "Checking repository..."
        }

        switch phase {
        case .idle:
            return nil
        case .checking:
            return "Checking repository..."
        case .generating:
            return "Generating commit message..."
        case .committing:
            return "Committing changes..."
        case .pushing:
            return "Pushing branch..."
        }
    }

    func load() async {
        guard !hasLoadedInitialState else {
            return
        }
        hasLoadedInitialState = true
        isLoadingInitialState = true
        defer { isLoadingInitialState = false }

        do {
            currentBranch = try await gitService.currentBranch(in: context.directory)
            branchSelection = currentBranch == context.baseBranch ? .base : .new
            try await refreshStagedPreflightIfNeeded()
        } catch {
            errorMessage = "Commit setup failed: \(error.localizedDescription)"
        }
    }

    func selectBaseBranch() {
        branchSelection = .base
        errorMessage = nil
    }

    func selectNewBranch() {
        branchSelection = .new
        errorMessage = nil
    }

    func perform(commitAndPush: Bool) async -> Bool {
        guard phase == .idle, !didCommitSuccessfully else {
            return false
        }

        errorMessage = nil
        phase = .checking
        do {
            try await validatePreflight()
            let resolvedMessage = try await resolvedCommitMessage()

            if branchSelection == .new, currentBranch != trimmedNewBranchName {
                phase = .committing
                try await gitService.checkoutNewBranch(trimmedNewBranchName, in: context.directory)
                currentBranch = trimmedNewBranchName
            }

            phase = .committing
            try await gitService.commit(
                message: resolvedMessage,
                includeUnstagedChanges: includeUnstagedChanges,
                in: context.directory
            )
            didCommitSuccessfully = true

            if commitAndPush {
                phase = .pushing
                do {
                    try await gitService.pushCurrentBranch(remoteName: context.remoteName, in: context.directory)
                } catch GitError.nonFastForwardPushRequired(_) {
                    forcePushRequired = true
                    phase = .idle
                    await refreshAfterMutation()
                    errorMessage = "Force push required."
                    return false
                } catch {
                    phase = .idle
                    await refreshAfterMutation()
                    errorMessage = "Commit succeeded, but push failed: \(error.localizedDescription)"
                    return false
                }
            }

            phase = .idle
            await refreshAfterMutation()
            return true
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            return false
        }
    }

    func performPrimaryAction() async -> Bool {
        if forcePushRequired {
            return await performForcePush()
        }
        return await perform(commitAndPush: true)
    }

    func performForcePush() async -> Bool {
        guard phase == .idle, forcePushRequired else {
            return false
        }

        errorMessage = nil
        phase = .pushing
        do {
            try await gitService.forcePushCurrentBranch(remoteName: context.remoteName, in: context.directory)
            forcePushRequired = false
            phase = .idle
            await refreshAfterMutation()
            return true
        } catch {
            phase = .idle
            errorMessage = error.localizedDescription
            return false
        }
    }

    static func defaultNewBranchName(branchPrefix: String, targetName: String) -> String {
        let slug = targetName
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: "-")
        return branchPrefix + slug
    }
}

private extension DiffGitCommitModalModel {
    var trimmedNewBranchName: String {
        newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func refreshStagedPreflight() async {
        guard !includeUnstagedChanges else {
            hasStagedChanges = nil
            return
        }

        isLoadingInitialState = true
        defer { isLoadingInitialState = false }
        do {
            try await refreshStagedPreflightIfNeeded()
        } catch {
            errorMessage = "Staged change check failed: \(error.localizedDescription)"
        }
    }

    func refreshStagedPreflightIfNeeded() async throws {
        if includeUnstagedChanges {
            hasStagedChanges = nil
        } else {
            hasStagedChanges = try await gitService.hasStagedChanges(in: context.directory)
        }
    }

    func validatePreflight() async throws {
        if currentBranch == nil {
            currentBranch = try await gitService.currentBranch(in: context.directory)
        }

        if branchSelection == .base,
           let currentBranch,
           currentBranch != context.baseBranch {
            throw DiffGitCommitModalError.message(
                "Current branch is `\(currentBranch)`; choose New branch to commit from here."
            )
        }

        if !includeUnstagedChanges {
            let hasStagedChanges = try await gitService.hasStagedChanges(in: context.directory)
            self.hasStagedChanges = hasStagedChanges
            guard hasStagedChanges else {
                throw DiffGitCommitModalError.message("No staged changes to commit.")
            }
        }

        if branchSelection == .new {
            guard !trimmedNewBranchName.isEmpty else {
                throw DiffGitCommitModalError.message("Enter a branch name.")
            }
            let isValidBranchName = try await gitService.validateBranchName(trimmedNewBranchName, in: context.directory)
            guard isValidBranchName else {
                throw DiffGitCommitModalError.message("Invalid branch name.")
            }
        }
    }

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

private enum DiffGitCommitModalError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
