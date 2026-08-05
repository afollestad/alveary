import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testArchivedScreenEmpty() throws {
        let fixture = try ArchivedSnapshotFixture(includeThreads: false)

        assertMacSnapshot(
            ArchivedScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "archived_empty"
        )
    }

    func testArchivedScreenPopulated() throws {
        let fixture = try ArchivedSnapshotFixture()

        assertMacSnapshot(
            ArchivedScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "archived_populated"
        )
    }

    func testArchivedScreenPopulatedDark() throws {
        let fixture = try ArchivedSnapshotFixture()

        assertMacSnapshot(
            ArchivedScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "archived_populated_dark",
            colorScheme: .dark
        )
    }

    func testArchivedScreenPopulatedNarrow() throws {
        let fixture = try ArchivedSnapshotFixture()

        assertMacSnapshot(
            ArchivedScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 620, height: 700),
            named: "archived_populated_narrow"
        )
    }

    /// The project name is long on purpose: the compact header caps the filter menu's
    /// width, and only an over-long label proves it truncates instead of pushing the
    /// search field off the pane.
    func testArchivedScreenPopulatedSqueezed() throws {
        let fixture = try ArchivedSnapshotFixture(includeLongNamedProject: true)
        fixture.viewModel.projectFilter = .project(path: ArchivedSnapshotFixture.longNamedProjectPath)

        assertMacSnapshot(
            ArchivedScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 420, height: 700),
            named: "archived_populated_squeezed"
        )
    }

    /// The project menu caps and truncates at every width, so an over-long name cannot
    /// push the search field off the pane even in the regular arrangement.
    func testArchivedHeaderLongProjectName() throws {
        let fixture = try ArchivedSnapshotFixture(includeLongNamedProject: true)
        fixture.viewModel.projectFilter = .project(path: ArchivedSnapshotFixture.longNamedProjectPath)

        assertMacSnapshot(
            ArchivedScreenHeader(
                searchQuery: .constant(""),
                projectFilter: .constant(fixture.viewModel.projectFilter),
                filterOptions: fixture.viewModel.projectFilterOptions,
                filterLabel: fixture.viewModel.projectFilterLabel
            ),
            size: CGSize(width: 700, height: 72),
            named: "archived_header_long_project_name"
        )
    }

    func testArchivedScreenNoSearchMatches() throws {
        let fixture = try ArchivedSnapshotFixture()
        fixture.viewModel.searchQuery = "nothing matches this"

        assertMacSnapshot(
            ArchivedScreen(viewModel: fixture.viewModel),
            size: CGSize(width: 1_120, height: 900),
            named: "archived_no_search_matches"
        )
    }
}

@MainActor
private final class ArchivedSnapshotFixture {
    let sidebarFixture: SidebarTestFixture
    let viewModel: ArchivedThreadsViewModel

    static let longNamedProjectPath = "/tmp/quarterly-platform-migration"

    init(includeThreads: Bool = true, includeLongNamedProject: Bool = false) throws {
        let sidebarFixture = try SidebarTestFixture()
        self.sidebarFixture = sidebarFixture

        var threads: [AgentThread] = []
        if includeThreads {
            threads = try Self.makeThreads(
                in: sidebarFixture,
                includeLongNamedProject: includeLongNamedProject
            )
            for thread in threads {
                sidebarFixture.context.insert(thread)
            }
            try sidebarFixture.context.save()
        }

        let orderedThreads = threads
        viewModel = ArchivedThreadsViewModel(
            modelContext: sidebarFixture.context,
            sidebarViewModel: sidebarFixture.viewModel,
            appState: AppState(),
            settingsService: sidebarFixture.settingsService,
            fetchArchivedThreads: { orderedThreads }
        )
        viewModel.refresh()
    }

    private static func makeThreads(
        in fixture: SidebarTestFixture,
        includeLongNamedProject: Bool
    ) throws -> [AgentThread] {
        let alveary = try fixture.insertProject(name: "Alveary", path: "/tmp/alveary")
        let skills = try fixture.insertProject(name: "Personal Skills", path: "/tmp/skills")

        var threads: [AgentThread] = []
        if includeLongNamedProject {
            let longNamed = try fixture.insertProject(
                name: "Quarterly Platform Migration Working Group",
                path: longNamedProjectPath
            )
            threads.append(
                makeProjectThread(
                    name: "Stage the migration checklist",
                    project: longNamed,
                    archivedAt: Date(timeIntervalSince1970: 1_795_000_000)
                )
            )
        }

        return threads + [
            makeTask(
                name: "Audit release notes",
                archivedAt: Date(timeIntervalSince1970: 1_800_000_000)
            ),
            makeTask(
                name: "Sweep stale worktrees",
                archivedAt: Date(timeIntervalSince1970: 1_799_000_000)
            ),
            makeProjectThread(
                name: "Retire stale MCP wiring",
                project: alveary,
                archivedAt: Date(timeIntervalSince1970: 1_798_000_000)
            ),
            makeProjectThread(
                name: "Split the transcript renderer",
                project: alveary,
                archivedAt: Date(timeIntervalSince1970: 1_797_000_000)
            ),
            makeProjectThread(
                name: "Document the skill manifest",
                project: skills,
                archivedAt: Date(timeIntervalSince1970: 1_796_000_000)
            )
        ]
    }

    private static func makeTask(name: String, archivedAt: Date) -> AgentThread {
        AgentThread(
            name: name,
            hasCustomName: true,
            archivedAt: archivedAt,
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/archived-snapshot-\(name)",
                ownershipStrategy: .projectLocal
            )
        )
    }

    private static func makeProjectThread(name: String, project: Project, archivedAt: Date) -> AgentThread {
        AgentThread(
            name: name,
            hasCustomName: true,
            archivedAt: archivedAt,
            project: project
        )
    }
}
