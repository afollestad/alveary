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

    init(includeThreads: Bool = true) throws {
        let sidebarFixture = try SidebarTestFixture()
        self.sidebarFixture = sidebarFixture

        var threads: [AgentThread] = []
        if includeThreads {
            let alveary = try sidebarFixture.insertProject(name: "Alveary", path: "/tmp/alveary")
            let skills = try sidebarFixture.insertProject(name: "Personal Skills", path: "/tmp/skills")

            threads = [
                Self.makeTask(
                    name: "Audit release notes",
                    archivedAt: Date(timeIntervalSince1970: 1_800_000_000)
                ),
                Self.makeTask(
                    name: "Sweep stale worktrees",
                    archivedAt: Date(timeIntervalSince1970: 1_799_000_000)
                ),
                Self.makeProjectThread(
                    name: "Retire stale MCP wiring",
                    project: alveary,
                    archivedAt: Date(timeIntervalSince1970: 1_798_000_000)
                ),
                Self.makeProjectThread(
                    name: "Split the transcript renderer",
                    project: alveary,
                    archivedAt: Date(timeIntervalSince1970: 1_797_000_000)
                ),
                Self.makeProjectThread(
                    name: "Document the skill manifest",
                    project: skills,
                    archivedAt: Date(timeIntervalSince1970: 1_796_000_000)
                )
            ]
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
