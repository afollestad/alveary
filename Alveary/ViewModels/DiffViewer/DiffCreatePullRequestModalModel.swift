import Foundation
import Observation

struct DiffCreatePullRequestModalContext: Identifiable, Equatable {
    let id = UUID()
    let directory: String
    let targetName: String
    let baseBranch: String
    let remoteName: String?
    /// The selection the created pull request links to automatically.
    let owner: PullRequestLinkOwner
}

/// Drives the create-pull-request modal: branch choice, title and description
/// (generated from the branch's commits when left blank), then branch → push →
/// `gh pr create`. Linking the result and opening its pane stay with the caller
/// — this model owns no `ModelContext`, the same split that keeps
/// `PullRequestsViewModel` context-free.
@MainActor
@Observable
final class DiffCreatePullRequestModalModel: Identifiable {
    enum OperationPhase: Equatable {
        case idle
        case checking
        case generating
        case branching
        case pushing
        case creating
    }

    static let titlePlaceholder = "Pull request title (leave blank to generate)..."
    static let descriptionPlaceholder = "Describe this pull request (leave blank to generate)..."

    let id = UUID()
    let context: DiffCreatePullRequestModalContext

    var branchSelection: DiffBranchSelection = .new
    var newBranchName: String {
        didSet {
            if oldValue != newBranchName {
                errorMessage = nil
            }
        }
    }

    var title = ""
    /// BlockInputKit store for the description; markdown serializes at submit,
    /// never per keystroke.
    let descriptionDraft: PullRequestCommentDraftBox

    var currentBranch: String?
    var commitsAhead: Int?
    var isLoadingInitialState = false
    var phase: OperationPhase = .idle
    var errorMessage: String?
    /// Resolved from the repository during `load()`; nil until then, and when
    /// the repository records no discoverable default.
    private(set) var resolvedBaseBranch: String?

    /// What this pull request merges into. `context.baseBranch` is only a hint —
    /// it comes from `Project.baseRef`, captured once at import — so a stale
    /// value would open the pull request against a different branch than the one
    /// the commit list and the ahead count are measured against.
    var baseBranch: String {
        resolvedBaseBranch ?? context.baseBranch
    }

    private let gitService: GitService
    private let pullRequestsService: any PullRequestsService
    private let settingsService: SettingsService
    private let generateText: @MainActor (String) async throws -> String
    private let refreshAfterMutation: @MainActor () async -> Void
    private var hasLoadedInitialState = false

    init(
        context: DiffCreatePullRequestModalContext,
        gitService: GitService,
        pullRequestsService: any PullRequestsService,
        settingsService: SettingsService,
        generateText: @escaping @MainActor (String) async throws -> String,
        refreshAfterMutation: @escaping @MainActor () async -> Void
    ) {
        self.context = context
        self.gitService = gitService
        self.pullRequestsService = pullRequestsService
        self.settingsService = settingsService
        self.generateText = generateText
        self.refreshAfterMutation = refreshAfterMutation
        self.descriptionDraft = PullRequestCommentDraftBox(markdown: "")
        self.newBranchName = DiffGitCommitModalModel.defaultNewBranchName(
            branchPrefix: settingsService.current.branchPrefix,
            targetName: context.targetName
        )
    }

    var controlsDisabled: Bool {
        isLoadingInitialState || phase != .idle
    }

    var createButtonDisabled: Bool {
        controlsDisabled || preflightMessage != nil
    }

    var isOperationInFlight: Bool {
        phase != .idle
    }

    var selectedBranchTitle: String {
        switch branchSelection {
        case .base:
            return baseBranch
        case .current:
            return currentBranch ?? baseBranch
        case .new:
            return "New branch"
        }
    }

    /// A pull request cannot merge the base branch into itself, so the base
    /// option is never selectable here — unlike the commit modal, which shares
    /// this menu.
    var isBaseBranchSelectable: Bool {
        false
    }

    var isCurrentBranchSelectable: Bool {
        guard let currentBranch else {
            return false
        }
        return currentBranch != baseBranch
    }

    var preflightMessage: String? {
        if branchSelection == .base {
            return "Create a new branch to open a pull request."
        }

        if branchSelection == .new, trimmedNewBranchName.isEmpty {
            return "Enter a branch name."
        }

        if commitsAhead == 0 {
            return "No commits ahead of `\(baseBranch)` to open a pull request for."
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
            return "Generating title and description..."
        case .branching:
            return "Creating branch..."
        case .pushing:
            return "Pushing branch..."
        case .creating:
            return "Creating pull request..."
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
            // Resolve the base first: the on-base check below and every later
            // read would otherwise be decided against the stale hint.
            resolvedBaseBranch = await gitService.defaultBranch(
                remoteName: context.remoteName,
                in: context.directory
            )
            currentBranch = try await gitService.currentBranch(in: context.directory)
            // Off base, the checkout is the natural head branch; on base, a new
            // branch is the only way to a valid pull request.
            branchSelection = currentBranch == baseBranch ? .new : .current
            commitsAhead = try await gitService.commitsAheadOfBase(
                baseBranch: baseBranch,
                remoteName: context.remoteName,
                in: context.directory
            )
        } catch {
            errorMessage = "Pull request setup failed: \(error.localizedDescription)"
        }
    }

    func selectCurrentBranch() {
        branchSelection = .current
        errorMessage = nil
    }

    func selectNewBranch() {
        branchSelection = .new
        errorMessage = nil
    }

    /// Runs the whole flow; nil on failure, with `errorMessage` naming the step
    /// that failed so a post-push failure is not mistaken for nothing happened.
    func submit() async -> PullRequestIdentifier? {
        guard phase == .idle else {
            return nil
        }

        errorMessage = nil
        phase = .checking
        do {
            try await validatePreflight()
            let content = try await resolvedContent()

            if branchSelection == .new, currentBranch != trimmedNewBranchName {
                phase = .branching
                try await gitService.checkoutNewBranch(trimmedNewBranchName, in: context.directory)
                currentBranch = trimmedNewBranchName
            }

            guard let headBranch = currentBranch else {
                throw DiffCreatePullRequestModalError.message("No branch is checked out.")
            }

            // An already-pushed branch exits 0 ("Everything up-to-date"), so
            // pushing unconditionally is safe and covers the never-pushed case.
            phase = .pushing
            try await gitService.pushCurrentBranch(remoteName: context.remoteName, in: context.directory)

            phase = .creating
            let identifier = try await pullRequestsService.createPullRequest(
                inDirectory: context.directory,
                baseBranch: baseBranch,
                headBranch: headBranch,
                title: content.title,
                body: content.body
            )

            phase = .idle
            await refreshAfterMutation()
            return identifier
        } catch {
            let failedPhase = phase
            phase = .idle
            errorMessage = Self.errorMessage(for: failedPhase, underlying: error)
            return nil
        }
    }
}

private extension DiffCreatePullRequestModalModel {
    var trimmedNewBranchName: String {
        newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Names the failed step: everything from `.branching` on has already
    /// mutated the repository, so the message must say what survived.
    static func errorMessage(for phase: OperationPhase, underlying error: Error) -> String {
        let description = error.localizedDescription
        switch phase {
        case .idle, .checking, .generating:
            return description
        case .branching:
            return "Branch creation failed: \(description)"
        case .pushing:
            return "Push failed: \(description)"
        case .creating:
            return "The branch was pushed, but creating the pull request failed: \(description)"
        }
    }

    func validatePreflight() async throws {
        if currentBranch == nil {
            currentBranch = try await gitService.currentBranch(in: context.directory)
        }

        if branchSelection == .base {
            throw DiffCreatePullRequestModalError.message("Create a new branch to open a pull request.")
        }

        if branchSelection == .current, currentBranch == baseBranch {
            throw DiffCreatePullRequestModalError.message("Create a new branch to open a pull request.")
        }

        if branchSelection == .new {
            guard !trimmedNewBranchName.isEmpty else {
                throw DiffCreatePullRequestModalError.message("Enter a branch name.")
            }
            let isValidBranchName = try await gitService.validateBranchName(trimmedNewBranchName, in: context.directory)
            guard isValidBranchName else {
                throw DiffCreatePullRequestModalError.message("Invalid branch name.")
            }
        }

        let aheadCount = try await gitService.commitsAheadOfBase(
            baseBranch: baseBranch,
            remoteName: context.remoteName,
            in: context.directory
        )
        commitsAhead = aheadCount
        guard aheadCount > 0 else {
            throw DiffCreatePullRequestModalError.message(
                "No commits ahead of `\(baseBranch)` to open a pull request for."
            )
        }
    }

    /// The typed title/description win; whichever is blank is generated — one
    /// call fills both, and the generated values are written back into the
    /// fields so the user sees what was submitted.
    func resolvedContent() async throws -> (title: String, body: String) {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let typedBody = descriptionDraft.isEffectivelyEmpty
            ? ""
            : descriptionDraft.markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty, !typedBody.isEmpty {
            return (trimmedTitle, typedBody)
        }

        phase = .generating
        let prompt = PullRequestGenerationPromptBuilder.build(
            editablePrompt: settingsService.current.pullRequestGenerationPrompt,
            context: try await generationContext()
        )
        let response = try await generateText(prompt)
        guard let parsed = PullRequestGenerationPromptBuilder.parseResponse(response) else {
            throw DiffCreatePullRequestModalError.message(
                "Pull request generation returned no content."
            )
        }

        let resolvedTitle = trimmedTitle.isEmpty ? parsed.title : trimmedTitle
        let resolvedBody = typedBody.isEmpty ? parsed.body : typedBody
        if trimmedTitle.isEmpty {
            title = resolvedTitle
        }
        if typedBody.isEmpty {
            descriptionDraft.resetContent(to: resolvedBody)
        }
        return (resolvedTitle, resolvedBody)
    }

    func generationContext() async throws -> String {
        let commits = try await gitService.commitsAheadOfBaseDetails(
            baseBranch: baseBranch,
            remoteName: context.remoteName,
            in: context.directory
        )
        var generationCommits: [PullRequestGenerationCommit] = []
        for commit in commits.prefix(PullRequestGenerationPromptBuilder.maxCommits) {
            // A commit whose diff cannot load still contributes its subject.
            let diff = (try? await gitService.diffForCommit(hash: commit.hash, in: context.directory)) ?? ""
            generationCommits.append(PullRequestGenerationCommit(subject: commit.message, diff: diff))
        }
        return PullRequestGenerationPromptBuilder.context(
            baseBranch: baseBranch,
            headBranch: branchSelection == .new ? trimmedNewBranchName : (currentBranch ?? ""),
            commitSubjects: commits.map(\.message),
            commits: generationCommits
        )
    }
}

private enum DiffCreatePullRequestModalError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
