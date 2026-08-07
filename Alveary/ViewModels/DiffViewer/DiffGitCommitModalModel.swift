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
    typealias BranchSelection = DiffBranchSelection

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

    /// The modal binds this box directly, so typing never serializes markdown.
    @ObservationIgnored let commitMessageDraft = AppMarkdownDraft(markdown: "")

    /// Plain-text bridge for callers that read or seed the message — generation,
    /// commit resolution, tests. Reading serializes the document, so keep it off
    /// per-keystroke paths.
    var commitMessage: String {
        get { commitMessageDraft.markdown }
        set { commitMessageDraft.resetContent(to: newValue) }
    }
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
    /// Resolved from the repository during `load()`; nil until then, and when
    /// the repository records no discoverable default.
    private(set) var resolvedBaseBranch: String?

    /// The branch this modal treats as the base. `context.baseBranch` is only a
    /// hint — it comes from `Project.baseRef`, captured once at import — and a
    /// stale value makes the "you are on base, commit to a new branch" gate fire
    /// on the wrong branch.
    var baseBranch: String {
        resolvedBaseBranch ?? context.baseBranch
    }

    // Shared with `DiffGitCommitModalModel+CommitMessage.swift`, which builds the
    // generation context; nothing outside this type's own files reads them.
    let gitService: GitService
    let settingsService: SettingsService
    let generateCommitMessage: @MainActor (String) async throws -> String
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
            return baseBranch
        case .current:
            return currentBranch ?? baseBranch
        case .new:
            return "New branch"
        }
    }

    var isBaseBranchSelectable: Bool {
        currentBranch == nil || currentBranch == baseBranch
    }

    /// The checked-out branch is only worth offering as its own choice when it
    /// is not the base branch; otherwise it is the same option twice.
    var isCurrentBranchSelectable: Bool {
        guard let currentBranch else {
            return false
        }
        return currentBranch != baseBranch
    }

    var preflightMessage: String? {
        if branchSelection == .base,
           let currentBranch,
           currentBranch != baseBranch {
            return "Current branch is `\(currentBranch)`; commit to it or choose New branch."
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
            // Resolve the base first: the on-base check below and every later
            // read would otherwise be decided against the stale hint.
            resolvedBaseBranch = await gitService.defaultBranch(
                remoteName: context.remoteName,
                in: context.directory
            )
            currentBranch = try await gitService.currentBranch(in: context.directory)
            // Off the base branch, the existing checkout is the expected commit
            // destination; a new branch stays available but is no longer implied.
            branchSelection = currentBranch == baseBranch ? .base : .current
            try await refreshStagedPreflightIfNeeded()
        } catch {
            errorMessage = "Commit setup failed: \(error.localizedDescription)"
        }
    }

    func selectBaseBranch() {
        branchSelection = .base
        errorMessage = nil
    }

    func selectCurrentBranch() {
        branchSelection = .current
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
           currentBranch != baseBranch {
            throw DiffGitCommitModalError.message(
                "Current branch is `\(currentBranch)`; commit to it or choose New branch."
            )
        }

        // `.current` commits in place, so it only needs a branch to exist.
        // Defensive: the re-fetch above leaves `currentBranch` non-nil unless it
        // threw, so this only fires if that invariant changes.
        if branchSelection == .current, currentBranch == nil {
            throw DiffGitCommitModalError.message("No branch is checked out.")
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
}

enum DiffGitCommitModalError: LocalizedError {
    case message(String)

    var errorDescription: String? {
        switch self {
        case .message(let message):
            return message
        }
    }
}
