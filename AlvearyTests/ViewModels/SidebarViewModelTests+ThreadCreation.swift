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

    func testCreateThreadUsesAutomaticEffortByDefault() async throws {
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
        XCTAssertEqual(savedThread.effort, "auto")
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
