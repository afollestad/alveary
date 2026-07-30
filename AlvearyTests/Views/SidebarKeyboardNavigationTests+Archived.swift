import SwiftData
import XCTest

@testable import Alveary

extension SidebarKeyboardNavigationTests {
    func testBuildNavigableItemsOmitsArchivedRowWhenNothingIsArchived() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        try context.save()

        let items = buildNavigableItems(
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] },
            hasArchivedThreads: false
        )

        XCTAssertEqual(items, [.skills, .mcp, .scheduled, .pullRequests, .project(project)])
    }

    func testBuildNavigableItemsPlacesArchivedAfterScheduledWhenArchivedThreadsExist() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        try context.save()

        let items = buildNavigableItems(
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] },
            hasArchivedThreads: true
        )

        XCTAssertEqual(items, [.skills, .mcp, .scheduled, .pullRequests, .archived, .project(project)])
    }

    func testBuildNavigableItemsOmitsPullRequestsRowWhenHidden() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        try context.save()

        let items = buildNavigableItems(
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] },
            hasArchivedThreads: false,
            showsPullRequests: false
        )

        XCTAssertEqual(items, [.skills, .mcp, .scheduled, .project(project)])
    }

    func testBuildNavigableItemsKeepsArchivedRowWhenPullRequestsIsHidden() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        try context.save()

        let items = buildNavigableItems(
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] },
            hasArchivedThreads: true,
            showsPullRequests: false
        )

        XCTAssertEqual(items, [.skills, .mcp, .scheduled, .archived, .project(project)])
    }

    func testArrowKeysSkipTheHiddenPullRequestsRow() throws {
        let project = makeProject(name: "Alpha", path: "/tmp/alpha")
        try context.save()

        let items = buildNavigableItems(
            projects: [project],
            expandedProjects: [],
            activeThreads: { _ in [] },
            hasArchivedThreads: false,
            showsPullRequests: false
        )

        XCTAssertEqual(navigateVertically(in: items, from: .scheduled, forward: true), .project(project))
        XCTAssertEqual(navigateVertically(in: items, from: .project(project), forward: false), .scheduled)
    }

    func testArrowKeysTraverseTheArchivedRowLikeOtherTopLevelRows() {
        let items: [SidebarItem] = [.skills, .mcp, .scheduled, .archived]

        XCTAssertEqual(navigateVertically(in: items, from: .scheduled, forward: true), .archived)
        XCTAssertEqual(navigateVertically(in: items, from: .archived, forward: false), .scheduled)
        XCTAssertTrue(shouldNavigateUpOnLeftArrow(selection: .archived, expandedProjects: []))
        XCTAssertTrue(shouldNavigateDownOnRightArrow(selection: .archived, expandedProjects: []))
    }
}
