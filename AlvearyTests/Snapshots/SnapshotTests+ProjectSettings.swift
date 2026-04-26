import XCTest

@testable import Alveary

extension SnapshotTests {
    func testProjectSettingsViewHidesGitHubForLocalProject() throws {
        let fixture = try SidebarTestFixture(gitHubInstalledVersion: "gh version 2.89.0", gitHubAuthenticated: false)
        let project = Project(path: "/tmp/local-project", name: "Local Project")
        let archivedThread = AgentThread(
            name: "Retire stale MCP wiring",
            archivedAt: Date(timeIntervalSince1970: 1_713_000_000),
            project: project
        )
        fixture.context.insert(project)
        fixture.context.insert(archivedThread)
        try fixture.context.save()
        let config = AlvearyProjectConfig.empty

        assertMacSnapshot(
            ProjectSettingsView(
                project: project,
                notificationManager: RecordingNotificationManager(),
                initialConfig: config,
                loadConfig: { _ in config }
            )
                .modelContainer(fixture.container),
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_local_project"
        )
    }

    func testProjectSettingsViewShowsGitHubRepoLink() throws {
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

        assertMacSnapshot(
            ProjectSettingsView(
                project: project,
                notificationManager: RecordingNotificationManager(),
                initialConfig: config,
                loadConfig: { _ in config }
            )
                .modelContainer(fixture.container),
            size: CGSize(width: 1100, height: 900),
            named: "project_settings_github_project"
        )
    }

    func testProjectSettingsViewNarrowStacksSplitInputs() throws {
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

        assertMacSnapshot(
            ProjectSettingsView(
                project: project,
                notificationManager: RecordingNotificationManager(),
                initialConfig: config,
                loadConfig: { _ in config }
            )
                .modelContainer(fixture.container),
            size: CGSize(width: 620, height: 900),
            named: "project_settings_narrow_split_inputs"
        )
    }
}
