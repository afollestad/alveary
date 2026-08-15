import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarViewCustomSectionWithThreads() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture(
            memberNames: ["Review release notes", "Draft changelog"],
            unsectionedNames: ["Loose task"]
        )

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_custom_section_populated"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: AppState())
        }
    }

    /// A custom section keeps its header and placeholder when empty; a section that vanished with
    /// its last thread would be impossible to drop onto.
    func testSidebarViewEmptyCustomSectionKeepsItsPlaceholder() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture()

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_custom_section_empty"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: AppState())
        }
    }

    func testSidebarViewCollapsedCustomSectionHidesItsThreads() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture(
            memberNames: ["Review release notes"]
        )

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_custom_section_collapsed"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel,
                appState: AppState(),
                initialCollapsedSections: [.custom(sidebar.sectionID)]
            )
        }
    }

    /// The pending name field mounts at the bottom, where the created section will land.
    func testSidebarViewPendingNewSectionRow() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture(memberNames: ["Review release notes"])

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_new_section_row"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel,
                appState: AppState(),
                initialIsCreatingSection: true
            )
        }
    }

    func testSidebarViewRenamingCustomSectionHeader() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture(memberNames: ["Review release notes"])

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_custom_section_renaming"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel,
                appState: AppState(),
                initialEditingSectionID: sidebar.sectionID
            )
        }
    }

    /// A section moved above `Pinned` renders there, proving the layout follows persisted order
    /// rather than statement order.
    func testSidebarViewCustomSectionOrderedFirst() async throws {
        let sidebar = try await makeCustomSectionSidebarSnapshotFixture(
            memberNames: ["Review release notes"]
        )
        try sidebar.fixture.viewModel.moveSection(id: .custom(sidebar.sectionID), before: .pinned)

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 720),
            named: "sidebar_custom_section_ordered_first"
        ) {
            SidebarView(viewModel: sidebar.fixture.viewModel, appState: AppState())
        }
    }
}

struct SnapshotCustomSectionSidebarFixture {
    let fixture: SidebarTestFixture
    let sectionID: String
    let members: [AgentThread]
}

@MainActor
func makeCustomSectionSidebarSnapshotFixture(
    sectionName: String = "Research",
    memberNames: [String] = [],
    unsectionedNames: [String] = []
) async throws -> SnapshotCustomSectionSidebarFixture {
    let fixture = try SidebarTestFixture()
    guard case .created(let descriptor) = try fixture.viewModel.createSection(name: sectionName),
          case .custom(let sectionID) = descriptor.id else {
        throw SnapshotCustomSectionFixtureError.sectionNotCreated
    }
    let section = fixture.context.resolveSidebarSection(id: sectionID)

    var members: [AgentThread] = []
    for (index, name) in (memberNames + unsectionedNames).enumerated() {
        let task = AgentThread(
            name: name,
            modifiedAt: Date(timeIntervalSince1970: 1_713_001_000 - Double(index)),
            mode: .task,
            taskWorkspaceDescriptor: TaskWorkspaceDescriptor(
                primaryRoot: "/tmp/sidebar-section-task-\(index)",
                ownershipStrategy: .projectLocal
            )
        )
        let conversation = Conversation(
            id: "sidebar-section-task-\(index)",
            title: "Main",
            provider: "claude",
            thread: task
        )
        task.conversations = [conversation]
        if index < memberNames.count {
            task.customSection = section
            members.append(task)
        }
        fixture.context.insert(task)
        fixture.context.insert(conversation)
    }
    try fixture.context.save()

    return SnapshotCustomSectionSidebarFixture(fixture: fixture, sectionID: sectionID, members: members)
}

enum SnapshotCustomSectionFixtureError: Error {
    case sectionNotCreated
}
