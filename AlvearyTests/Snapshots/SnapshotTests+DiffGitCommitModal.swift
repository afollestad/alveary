import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testDiffGitCommitModalBaseBranch() async {
        let model = diffGitCommitModalModel(currentBranch: "main")
        await model.load()

        assertMacSnapshot(
            DiffGitCommitModal(model: model, onClose: {}),
            size: CGSize(width: 620, height: 360),
            named: "diff_git_commit_modal_base_branch"
        )
    }

    func testDiffGitCommitModalNewBranch() async {
        let model = diffGitCommitModalModel(
            threadName: "Disable Steering During Handoff",
            currentBranch: "feature/current"
        )
        await model.load()

        assertMacSnapshot(
            DiffGitCommitModal(model: model, onClose: {}),
            size: CGSize(width: 620, height: 400),
            named: "diff_git_commit_modal_new_branch"
        )
    }

    func testDiffGitCommitModalNoStagedChangesDisabled() async {
        var settings = AppSettings()
        settings.gitCommitIncludeUnstagedChanges = false
        let model = diffGitCommitModalModel(settings: settings, currentBranch: "main")
        await model.load()

        assertMacSnapshot(
            DiffGitCommitModal(model: model, onClose: {}),
            size: CGSize(width: 620, height: 430),
            named: "diff_git_commit_modal_no_staged_changes"
        )
    }

    func testDiffGitCommitModalGenerating() async {
        let model = diffGitCommitModalModel(currentBranch: "main")
        await model.load()
        model.phase = .generating

        assertMacSnapshot(
            DiffGitCommitModal(model: model, onClose: {}),
            size: CGSize(width: 620, height: 390),
            named: "diff_git_commit_modal_generating"
        )
    }
}

private extension SnapshotTests {
    func diffGitCommitModalModel(
        threadName: String = "Commit Modal",
        settings: AppSettings = {
            var settings = AppSettings()
            settings.branchPrefix = "af/"
            return settings
        }(),
        currentBranch: String = "main"
    ) -> DiffGitCommitModalModel {
        DiffGitCommitModalModel(
            context: DiffGitCommitModalContext(
                directory: "/tmp/alveary-snapshot-project",
                threadName: threadName,
                baseBranch: "main",
                remoteName: "origin"
            ),
            gitService: SnapshotMockGitService(
                statusResults: [[]],
                diffResults: [],
                hasStagedChangesResult: settings.gitCommitIncludeUnstagedChanges,
                currentBranchResult: currentBranch
            ),
            settingsService: InMemorySettingsService(current: settings),
            generateCommitMessage: { _ in "Generated commit message" },
            refreshAfterMutation: {}
        )
    }
}
