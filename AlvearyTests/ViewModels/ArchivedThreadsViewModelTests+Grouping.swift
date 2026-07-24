import SwiftData
import XCTest

@testable import Alveary

@MainActor
extension ArchivedThreadsViewModelTests {
    func testSectionsPlaceProjectlessThreadsFirstWithoutTitleThenProjectsByName() throws {
        let fixture = try SidebarTestFixture()
        let zebra = try fixture.insertProject(name: "Zebra", path: "/tmp/zebra")
        let apple = try fixture.insertProject(name: "Apple", path: "/tmp/apple")
        let standalone = try insertTask(in: fixture, name: "Standalone", archivedAt: Date(timeIntervalSince1970: 100))
        let zebraThread = try insertProjectThread(
            in: fixture,
            name: "Zebra thread",
            project: zebra,
            archivedAt: Date(timeIntervalSince1970: 200)
        )
        let appleThread = try insertProjectThread(
            in: fixture,
            name: "Apple thread",
            project: apple,
            archivedAt: Date(timeIntervalSince1970: 300)
        )
        let viewModel = makeViewModel(fixture: fixture).viewModel

        viewModel.refresh()

        XCTAssertEqual(viewModel.sections.map(\.title), [nil, "Apple", "Zebra"])
        XCTAssertEqual(viewModel.sections.map { $0.items.map(\.id) }, [
            [standalone.persistentModelID],
            [appleThread.persistentModelID],
            [zebraThread.persistentModelID]
        ])
    }

    func testSearchQueryFiltersSectionsByTitleCaseInsensitively() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary")
        _ = try insertTask(in: fixture, name: "Standalone chore", archivedAt: Date(timeIntervalSince1970: 100))
        let match = try insertProjectThread(
            in: fixture,
            name: "Refactor SIDEBAR",
            project: project,
            archivedAt: Date(timeIntervalSince1970: 200)
        )
        let viewModel = makeViewModel(fixture: fixture).viewModel
        viewModel.refresh()

        viewModel.searchQuery = "sidebar"

        XCTAssertEqual(viewModel.sections.map(\.title), ["Alveary"])
        XCTAssertEqual(viewModel.sections.flatMap { $0.items.map(\.id) }, [match.persistentModelID])
    }

    func testProjectFilterOptionsCoverOnlyBucketsThatHaveArchivedThreads() throws {
        let fixture = try SidebarTestFixture()
        let used = try fixture.insertProject(name: "Used", path: "/tmp/used")
        _ = try fixture.insertProject(name: "Unused", path: "/tmp/unused")
        _ = try insertProjectThread(in: fixture, name: "Kept", project: used, archivedAt: Date())
        let viewModel = makeViewModel(fixture: fixture).viewModel

        viewModel.refresh()

        XCTAssertEqual(viewModel.projectFilterOptions, [.all, .project(path: "/tmp/used")])
        XCTAssertEqual(viewModel.projectFilterLabel(.all), "All Projects")
        XCTAssertEqual(viewModel.projectFilterLabel(.project(path: "/tmp/used")), "Used")
    }

    func testProjectFilterNarrowsToOneBucketAndFallsBackToAllWhenItEmpties() async throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Scoped", path: "/tmp/scoped")
        _ = try insertTask(in: fixture, name: "Standalone", archivedAt: Date(timeIntervalSince1970: 100))
        let projectThread = try insertProjectThread(
            in: fixture,
            name: "Scoped thread",
            project: project,
            archivedAt: Date(timeIntervalSince1970: 200)
        )
        let viewModel = makeViewModel(fixture: fixture).viewModel
        viewModel.refresh()

        viewModel.projectFilter = .project(path: "/tmp/scoped")
        XCTAssertEqual(viewModel.sections.map(\.title), ["Scoped"])
        XCTAssertEqual(viewModel.sections.flatMap { $0.items.map(\.id) }, [projectThread.persistentModelID])

        await viewModel.restore(try XCTUnwrap(viewModel.sections.first?.items.first))

        XCTAssertEqual(viewModel.projectFilter, .all)
        XCTAssertEqual(viewModel.sections.map(\.title), [nil])
    }

    func testProjectlessFilterKeepsOnlyThreadsWithNoProject() throws {
        let fixture = try SidebarTestFixture()
        let project = try fixture.insertProject(name: "Scoped", path: "/tmp/scoped")
        let standalone = try insertTask(in: fixture, name: "Standalone", archivedAt: Date(timeIntervalSince1970: 100))
        _ = try insertProjectThread(
            in: fixture,
            name: "Scoped thread",
            project: project,
            archivedAt: Date(timeIntervalSince1970: 200)
        )
        let viewModel = makeViewModel(fixture: fixture).viewModel
        viewModel.refresh()

        viewModel.projectFilter = .noProject

        XCTAssertEqual(viewModel.sections.map(\.title), [nil])
        XCTAssertEqual(viewModel.sections.flatMap { $0.items.map(\.id) }, [standalone.persistentModelID])
    }
}
