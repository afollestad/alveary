import Foundation
import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension SidebarViewModelTests {
    func testNormalizationRepairsDuplicateGappedMixedPinnedOrderBeforeAppendingMissingItems() throws {
        let fixture = try SidebarTestFixture()
        let manualProject = Project(
            path: "/tmp/manual-project",
            name: "Alpha",
            isPinned: true,
            pinnedSortOrder: 8
        )
        let manualOwner = Project(path: "/tmp/manual-owner", name: "Manual Owner")
        let manualThread = AgentThread(
            name: "Zulu",
            isPinned: true,
            pinnedSortOrder: 8,
            modifiedAt: Date(timeIntervalSince1970: 900),
            project: manualOwner
        )
        manualOwner.threads = [manualThread]
        let missingProject = Project(path: "/tmp/missing-project", name: "Missing Project", isPinned: true)
        let missingProjectChild = AgentThread(
            name: "Recent Child",
            modifiedAt: Date(timeIntervalSince1970: 500),
            project: missingProject
        )
        missingProject.threads = [missingProjectChild]
        let missingOwner = Project(path: "/tmp/missing-owner", name: "Missing Owner")
        let missingThread = AgentThread(
            name: "Missing Thread",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 300),
            project: missingOwner
        )
        missingOwner.threads = [missingThread]
        fixture.context.insert(manualProject)
        fixture.context.insert(manualOwner)
        fixture.context.insert(missingProject)
        fixture.context.insert(missingOwner)
        try fixture.context.save()

        try fixture.viewModel.ensureSidebarOrderingInitialized()

        XCTAssertEqual(manualProject.pinnedSortOrder, 0)
        XCTAssertEqual(manualThread.pinnedSortOrder, 1)
        XCTAssertEqual(missingProject.pinnedSortOrder, 2)
        XCTAssertEqual(missingThread.pinnedSortOrder, 3)
    }

    func testNoOpDropPersistsNecessaryNormalizationWhileReturningFalse() throws {
        let fixture = try SidebarTestFixture()
        let first = Project(path: "/tmp/first", name: "First", sidebarSortOrder: 0)
        let second = Project(path: "/tmp/second", name: "Second", sidebarSortOrder: 7)
        fixture.context.insert(first)
        fixture.context.insert(second)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(first.persistentModelID),
            target: SidebarDropTarget(
                section: .projects,
                item: .project(second.persistentModelID),
                placement: .before
            )
        )

        XCTAssertFalse(didCommit)
        XCTAssertFalse(fixture.context.hasChanges)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 1)
        let verificationContext = ModelContext(fixture.container)
        let persistedProjects = try verificationContext.fetch(FetchDescriptor<Project>())
        XCTAssertEqual(
            fixture.viewModel.regularProjects(from: persistedProjects).compactMap(\.sidebarSortOrder),
            [0, 1]
        )
    }

    func testDropRejectsDeletedSourceWithoutMutatingSurvivor() throws {
        let fixture = try SidebarTestFixture()
        let deleted = Project(path: "/tmp/deleted", name: "Deleted", sidebarSortOrder: 0)
        let survivor = Project(path: "/tmp/survivor", name: "Survivor", sidebarSortOrder: 1)
        fixture.context.insert(deleted)
        fixture.context.insert(survivor)
        try fixture.context.save()
        let deletedID = deleted.persistentModelID
        fixture.context.delete(deleted)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(deletedID),
            target: SidebarDropTarget(
                section: .projects,
                item: .project(survivor.persistentModelID),
                placement: .before
            )
        )

        XCTAssertFalse(didCommit)
        XCTAssertEqual(survivor.sidebarSortOrder, 1)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }

    func testDropRejectsDeletedAnchorWithoutMutatingSource() throws {
        let fixture = try SidebarTestFixture()
        let source = Project(path: "/tmp/source", name: "Source", sidebarSortOrder: 0)
        let deletedAnchor = Project(path: "/tmp/anchor", name: "Anchor", sidebarSortOrder: 1)
        fixture.context.insert(source)
        fixture.context.insert(deletedAnchor)
        try fixture.context.save()
        let deletedAnchorID = deletedAnchor.persistentModelID
        fixture.context.delete(deletedAnchor)
        try fixture.context.save()

        let didCommit = try fixture.viewModel.commitSidebarDrop(
            dragItem: .project(source.persistentModelID),
            target: SidebarDropTarget(
                section: .projects,
                item: .project(deletedAnchorID),
                placement: .after
            )
        )

        XCTAssertFalse(didCommit)
        XCTAssertEqual(source.sidebarSortOrder, 0)
        XCTAssertEqual(fixture.viewModel.threadOrderVersion, 0)
    }
}
