import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testProjectSettingsShowsSelectedFolderInMultiFolderProject() async throws {
        let fixture = try SidebarTestFixture()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = [
            SourceFolderSnapshot(path: "\(home)/Development/AgentCLIKit", gitBranch: "develop", baseRef: "develop"),
            SourceFolderSnapshot(path: "\(home)/Development/alveary", gitBranch: "main", baseRef: "main")
        ]
        let project = Project(name: "AgentCLIKit", folders: folders, primaryFolderPath: folders[1].path)
        fixture.context.insert(project)
        try fixture.context.save()
        let selection = WorkspaceFolderSelection()
        let owner = WorkspaceFolderOwner.project(project.id)

        for isPrimary in [true, false] {
            if !isPrimary { selection.select(project.workspaceFolderTargets[0], owner: owner) }
            let selected = try XCTUnwrap(selection.selected(in: project.workspaceFolderTargets, owner: owner))
            let config = AlvearyProjectConfig(setupScript: isPrimary ? "./scripts/setup.sh" : "swift package resolve")
            await assertMacModelSnapshot(
                modelContainer: fixture.container,
                size: CGSize(width: 900, height: 850),
                named: "project_settings_multiple_\(isPrimary ? "primary" : "secondary")",
                colorScheme: .dark
            ) {
                ProjectSettingsView(
                    project: project, appState: AppState(), sidebarViewModel: fixture.viewModel,
                    initialConfig: config, sourceFolder: selected.source, loadConfig: { _ in config }
                )
            }
        }
    }

    func testProjectSettingsViewHidesGitHubForLocalProject() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(path: "/tmp/local-project", name: "Local Project")
        fixture.context.insert(project)
        try fixture.context.save()
        let config = AlvearyProjectConfig.empty

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_local_project"
        ) {
            ProjectSettingsView(
                project: project,
                appState: AppState(),
                sidebarViewModel: fixture.viewModel,
                initialConfig: config,
                loadConfig: { _ in config }
            )
        }
    }

    func testProjectSettingsNarrowMultiFolderLongNames() async throws {
        let fixture = try SidebarTestFixture()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let folders = [
            SourceFolderSnapshot(
                path: "\(home)/Development/Workspace/Alveary-macOS-application-and-tools",
                gitBranch: "main", baseRef: "main"
            ),
            SourceFolderSnapshot(
                path: "\(home)/Development/Workspace/AgentCLIKit-provider-integration-and-runtime",
                gitBranch: "develop", baseRef: "develop"
            )
        ]
        let project = Project(
            name: "Alveary macOS development and companion libraries",
            folders: folders,
            primaryFolderPath: folders[0].path
        )
        fixture.context.insert(project)
        try fixture.context.save()
        let config = AlvearyProjectConfig(setupScript: "swift package resolve")

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 420, height: 900),
            named: "project_settings_narrow_multiple_long_names",
            colorScheme: .dark
        ) {
            ProjectSettingsView(
                project: project,
                appState: AppState(),
                sidebarViewModel: fixture.viewModel,
                initialConfig: config,
                sourceFolder: folders[1],
                loadConfig: { _ in config }
            )
        }
    }

    func testProjectSettingsViewShowsGitHubRepoLink() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(
            path: "/tmp/github-project",
            name: "GitHub Project",
            gitRemote: "https://github.com/afollestad/personal-ai-skills.git",
            remoteName: "origin",
            gitBranch: "main",
            baseRef: "main",
            githubRepository: "afollestad/personal-ai-skills"
        )
        fixture.context.insert(project)
        try fixture.context.save()
        let config = AlvearyProjectConfig(
            setupScript: "bin/setup-dev",
            teardownScript: "bin/cleanup-dev",
            preservePatterns: [".env", ".env.local", "config/*.json"],
            actions: [
                .init(icon: "hammer", name: "Build", command: "./scripts/build.sh"),
                .init(icon: "checkmark.circle", name: "Test", command: "./scripts/test.sh"),
                .init(icon: "sparkles", name: "Generate", command: "make generate")
            ]
        )

        for scheme in [ColorScheme.light, .dark] {
            await assertMacModelSnapshot(
                modelContainer: fixture.container,
                size: CGSize(width: 1100, height: 900),
                named: "project_settings_github_project" + (scheme == .dark ? "_dark" : ""),
                colorScheme: scheme
            ) {
                ProjectSettingsView(
                    project: project,
                    appState: AppState(),
                    sidebarViewModel: fixture.viewModel,
                    initialConfig: config,
                    loadConfig: { _ in config }
                )
            }
        }
    }

    func testProjectSettingsViewNarrowStacksSplitInputs() async throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(
            path: "/tmp/github-project",
            name: "GitHub Project",
            gitRemote: "https://github.com/afollestad/personal-ai-skills.git",
            remoteName: "origin",
            gitBranch: "main",
            baseRef: "main",
            githubRepository: "afollestad/personal-ai-skills"
        )
        fixture.context.insert(project)
        try fixture.context.save()
        let config = AlvearyProjectConfig(
            setupScript: "bin/setup-dev",
            teardownScript: "bin/cleanup-dev",
            preservePatterns: [".env", ".env.local", "config/*.json"],
            actions: [
                .init(icon: "hammer", name: "Build", command: "./scripts/build.sh")
            ]
        )

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 620, height: 900),
            named: "project_settings_narrow_split_inputs"
        ) {
            ProjectSettingsView(
                project: project,
                appState: AppState(),
                sidebarViewModel: fixture.viewModel,
                initialConfig: config,
                loadConfig: { _ in config }
            )
        }
    }

    func testProjectSettingsViewWithoutFolders() async throws {
        let fixture = try SidebarTestFixture()
        let project = Project(name: "Research")
        fixture.context.insert(project)
        try fixture.context.save()

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 620, height: 400),
            named: "project_settings_without_folders",
            colorScheme: .dark
        ) {
            ProjectSettingsView(
                project: project,
                appState: AppState(),
                sidebarViewModel: fixture.viewModel,
                loadConfig: { _ in .empty }
            )
        }
    }

    func testProjectSettingsRepositorySummaryWrapsLongValues() {
        let sourceFolder = SourceFolderSnapshot(
            path: "/tmp/github-project",
            gitRemote: "https://github.com/afollestad/project-settings-accessibility-and-worktree-configuration.git",
            remoteName: "upstream",
            gitBranch: "release/2026-09-project-settings-accessibility-polish",
            baseRef: "release/2026-09-project-settings-accessibility-polish",
            githubRepository: "afollestad/project-settings-accessibility-and-worktree-configuration"
        )

        assertMacSnapshot(
            ProjectSettingsRepositoryCard(sourceFolder: sourceFolder)
                .padding(20),
            size: CGSize(width: 620, height: 140),
            named: "project_settings_git_summary_long_values"
        )
    }

    func testProjectSettingsActionIconGrid() {
        for scheme in [ColorScheme.light, .dark] {
            assertMacSnapshot(
                ProjectSettingsActionIconGrid(symbolName: "arrow.triangle.branch", onSelect: { _ in }),
                size: CGSize(width: 318, height: 356),
                named: "project_settings_action_icon_grid_\(scheme)",
                colorScheme: scheme
            )
        }
    }
}
