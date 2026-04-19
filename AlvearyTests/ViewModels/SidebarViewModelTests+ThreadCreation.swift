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
            permissionMode: "plan"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.name, "New thread")
        XCTAssertEqual(savedThread.permissionMode, "plan")
        XCTAssertEqual(savedThread.effort, "max")
        XCTAssertTrue(savedThread.useWorktree)
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
            permissionMode: "plan"
        )

        let savedThread = try fixture.requireThread(thread)
        XCTAssertEqual(savedThread.project?.path, project.path)
        XCTAssertFalse(savedThread.useWorktree)
        XCTAssertEqual(savedThread.effort, "max")
        XCTAssertEqual(savedThread.conversations.count, 1)
    }
}
