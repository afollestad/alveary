import AgentCLIKit
import Foundation
import SwiftData
import XCTest

@testable import Alveary

extension SidebarViewModelTests {
    func testCreateThreadSeedsDefaultsAndInitialConversationForGitProjects() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "max", createWorktreeByDefault: true)
        let project = Project(
            path: "/tmp/alveary-project",
            name: "Alveary",
            gitBranch: "feature/auth",
            baseRef: "main"
        )
        fixture.context.insert(project)
        try fixture.context.save()

        let readContext = ModelContext(fixture.container)
        let externalProject = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Project>()).first
        )

        let thread = try await fixture.viewModel.createThread(
            project: externalProject,
            provider: "claude",
            permissionMode: "acceptEdits"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.name, "New thread")
        XCTAssertEqual(savedThread.permissionMode, "acceptEdits")
        XCTAssertEqual(savedThread.effort, "max")
        XCTAssertTrue(savedThread.useWorktree)
        XCTAssertFalse(savedThread.isPinned)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertEqual(savedThread.conversations.count, 1)
        XCTAssertEqual(savedThread.conversations.first?.provider, "claude")
        XCTAssertTrue(savedThread.conversations.first?.isMain ?? false)
        XCTAssertEqual(savedThread.conversations.first?.displayOrder, 0)
    }

    func testCreateThreadSeedsNilModelWhenDefaultModelSettingIsDefault() async throws {
        let fixture = try SidebarTestFixture(defaultModel: AppSettings.defaultModelValue)
        let project = try fixture.insertProject(name: "Plain", path: "/tmp/plain-default-model")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        XCTAssertNil(try fixture.requireThread(thread).model)
    }

    func testCreateThreadSeedsModelFromAppDefaultWhenOverridden() async throws {
        let fixture = try SidebarTestFixture(defaultModel: "opus")
        let project = try fixture.insertProject(name: "Plain", path: "/tmp/plain-opus-default")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        XCTAssertEqual(try fixture.requireThread(thread).model, "opus")
    }

    func testCreateThreadUsesMediumEffortByDefault() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Plain Folder", path: "/tmp/plain-folder")

        let readContext = ModelContext(fixture.container)
        let externalProject = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Project>()).first
        )

        let thread = try await fixture.viewModel.createThread(
            project: externalProject,
            provider: "claude",
            permissionMode: "default"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertEqual(savedThread.effort, AppSettings.defaultEffortLevel)
    }

    // Thread creation uses the already-normalized settings value. Settings UI
    // owns applying model-scoped defaults when the user changes the model.
    func testCreateThreadSeedsNormalizedSettingsEffortForSelectedModel() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "xhigh", defaultModel: "opus")
        let project = try fixture.insertProject(name: "Opus Project", path: "/tmp/opus-default")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.model, "opus")
        XCTAssertEqual(savedThread.effort, "xhigh")
    }

    // A user who explicitly picked a non-default effort in Settings (e.g. "high")
    // expects that choice to win over the per-model default, as long as the
    // value is valid for the new thread's model.
    func testCreateThreadPrefersCustomizedSettingsEffortOverPerModelDefault() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "high", defaultModel: "opus")
        let project = try fixture.insertProject(name: "Opus Project", path: "/tmp/opus-high")

        let thread = try await fixture.viewModel.createThread(
            project: project,
            provider: "claude",
            permissionMode: "default"
        )

        XCTAssertEqual(try fixture.requireThread(thread).effort, "high")
    }

    func testCreateThreadDefaultPathUsesReadyProviderFallback() async throws {
        let fixture = try SidebarTestFixture(
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: SettingsViewModelTests.providerStatus(
                    for: .claude,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: SettingsViewModelTests.providerStatus(
                    for: .codex,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )
        fixture.settingsService.update {
            $0.defaultProvider = "codex"
            $0.defaultModel = "gpt-5.4-mini"
            $0.permissionMode = "never"
        }
        let project = try fixture.insertProject(name: "Fallback Project", path: "/tmp/provider-fallback")

        let thread = try await fixture.viewModel.createThread(project: project)

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.model, nil)
        XCTAssertEqual(savedThread.permissionMode, "default")
        XCTAssertEqual(savedThread.conversations.first?.provider, "claude")
    }

    func testCreateThreadDefaultPathFailsWhenNoProviderIsReady() async throws {
        let fixture = try SidebarTestFixture(
            providerDiscovery: RecordingProviderDiscoveryService(statuses: [
                .claude: SettingsViewModelTests.providerStatus(
                    for: .claude,
                    installation: .missing,
                    modelOptions: AgentModelOptionTestFixtures.claudeModelOptions
                ),
                .codex: SettingsViewModelTests.providerStatus(
                    for: .codex,
                    setup: .needsSetup,
                    modelOptions: AgentModelOptionTestFixtures.codexModelOptions
                )
            ])
        )
        let project = try fixture.insertProject(name: "No Providers", path: "/tmp/no-ready-providers")

        do {
            _ = try await fixture.viewModel.createThread(project: project)
            XCTFail("Expected no-ready-provider failure")
        } catch SidebarViewModelError.noReadyThreadDefaultProvider {
            XCTAssertTrue(fixture.context.hasChanges == false)
        }
    }

    func testCreateThreadDisablesWorktreeDefaultForNonGitProjects() async throws {
        let fixture = try SidebarTestFixture(defaultEffort: "max", createWorktreeByDefault: true)
        let project = try fixture.insertProject(name: "Plain Folder", path: "/tmp/plain-folder")

        let readContext = ModelContext(fixture.container)
        let externalProject = try XCTUnwrap(
            try readContext.fetch(FetchDescriptor<Project>()).first
        )

        let thread = try await fixture.viewModel.createThread(
            project: externalProject,
            provider: "claude",
            permissionMode: "acceptEdits"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertFalse(savedThread.useWorktree)
        XCTAssertEqual(savedThread.effort, "max")
        XCTAssertEqual(savedThread.conversations.count, 1)
    }
}
