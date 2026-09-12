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

        await assertMacModelSnapshot(
            modelContainer: fixture.container,
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_github_project"
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
}
