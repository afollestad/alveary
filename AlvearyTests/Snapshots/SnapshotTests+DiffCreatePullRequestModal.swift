import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    /// Off base: the dropdown names the checked-out branch, no branch field.
    func testDiffCreatePullRequestModalCurrentBranch() async throws {
        let model = try diffCreatePullRequestModalModel(currentBranch: "feature/current")
        await model.load()

        assertMacSnapshot(
            DiffCreatePullRequestModal(model: model, onCreated: { _ in }, onClose: {}),
            size: CGSize(width: 620, height: 380),
            named: "diff_create_pull_request_modal_current_branch"
        )
    }

    /// On base: a pull request needs a new branch, so the prefixed name field
    /// shows and the base row stays unselectable.
    func testDiffCreatePullRequestModalNewBranch() async throws {
        let model = try diffCreatePullRequestModalModel(currentBranch: "main")
        await model.load()

        assertMacSnapshot(
            DiffCreatePullRequestModal(model: model, onCreated: { _ in }, onClose: {}),
            size: CGSize(width: 620, height: 420),
            named: "diff_create_pull_request_modal_new_branch"
        )
    }

    func testDiffCreatePullRequestModalNoCommitsAheadPreflight() async throws {
        let model = try diffCreatePullRequestModalModel(currentBranch: "feature/current", commitsAhead: 0)
        await model.load()

        assertMacSnapshot(
            DiffCreatePullRequestModal(model: model, onCreated: { _ in }, onClose: {}),
            size: CGSize(width: 620, height: 430),
            named: "diff_create_pull_request_modal_no_commits"
        )
    }

    func testDiffCreatePullRequestModalGenerating() async throws {
        let model = try diffCreatePullRequestModalModel(currentBranch: "feature/current")
        await model.load()
        model.phase = .generating

        assertMacSnapshot(
            DiffCreatePullRequestModal(model: model, onCreated: { _ in }, onClose: {}),
            size: CGSize(width: 620, height: 400),
            named: "diff_create_pull_request_modal_generating"
        )
    }

    func testDiffCreatePullRequestModalError() async throws {
        let model = try diffCreatePullRequestModalModel(currentBranch: "feature/current")
        await model.load()
        model.errorMessage = "The branch was pushed, but creating the pull request failed: HTTP 422"

        assertMacSnapshot(
            DiffCreatePullRequestModal(model: model, onCreated: { _ in }, onClose: {}),
            size: CGSize(width: 620, height: 440),
            named: "diff_create_pull_request_modal_error"
        )
    }
}

private extension SnapshotTests {
    func diffCreatePullRequestModalModel(
        currentBranch: String,
        commitsAhead: Int = 2
    ) throws -> DiffCreatePullRequestModalModel {
        var settings = AppSettings()
        settings.branchPrefix = "af/"
        let container = try ModelContainer(
            for: Project.self,
            AgentThread.self,
            Conversation.self,
            ConversationEventRecord.self,
            ScheduledTask.self,
            ScheduledTaskRun.self,
            ScheduledTaskProposal.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let context = ModelContext(container)
        let thread = AgentThread(name: "Thread")
        context.insert(thread)
        try context.save()

        return DiffCreatePullRequestModalModel(
            context: DiffCreatePullRequestModalContext(
                directory: "/tmp/alveary-snapshot-project",
                targetName: "Create PR Modal",
                baseBranch: "main",
                remoteName: "origin",
                owner: .thread(thread.persistentModelID)
            ),
            gitService: SnapshotMockGitService(
                statusResults: [[]],
                diffResults: [],
                currentBranchResult: currentBranch,
                commitsAheadResult: commitsAhead
            ),
            pullRequestsService: StubPullRequestsService(),
            settingsService: InMemorySettingsService(current: settings),
            generateText: { _ in "Generated title\n\nGenerated body." },
            refreshAfterMutation: {}
        )
    }
}
