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

    /// Right-clicking a collapsed section's header outlines that header alone — the divider above
    /// it stays outside, which the SwiftUI `contextMenu` this replaced could not manage. The
    /// expanded shape is already locked by `sidebar_drag_custom_section_border`.
    func testSidebarCollapsedSectionSecondaryClickHighlightsTheHeaderAlone() {
        assertMacSnapshot(
            SidebarCollapsedSectionHighlightSnapshot(),
            size: CGSize(width: 320, height: 200),
            named: "sidebar_section_secondary_click_highlight"
        )
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

/// A collapsed custom section outlined as its open secondary-click menu leaves it: the header's
/// title row plus the container outset, and none of the divider's spacing above it.
///
/// The frame is measured through the real publisher rather than hardcoded — the header emits
/// `.customSectionHeader` exactly as production does, and `sidebarSectionContainerFrame` composes
/// it with no content frames, which is what a collapsed section leaves behind.
private struct SidebarCollapsedSectionHighlightSnapshot: View {
    private static let sectionID = "research"

    @State private var geometry: [SidebarDragGeometryRole: [CGRect]] = [:]

    var body: some View {
        List {
            SidebarSectionHeaderRow(title: "Projects", showsTopDivider: true, onAddProject: {})

            Text("No projects yet")
                .foregroundStyle(.secondary)
                .padding(.leading, SidebarSectionHeaderRow.titleInkLeadingPadding)

            SidebarSectionHeaderRow(
                title: "Research",
                showsTopDivider: true,
                disclosure: SidebarSectionHeaderDisclosure(isExpanded: false, onToggle: {})
            )
            .sidebarDragGeometry(
                .customSectionHeader(Self.sectionID),
                excludingTopInset: SidebarSectionHeaderRow.inlineHeaderTotalTopPadding
            )
        }
        .listStyle(.sidebar)
        .coordinateSpace(name: SidebarDragCoordinateSpace.name)
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: SidebarDragGeometryPreferenceKey.self,
                    value: [.viewport: [proxy.frame(in: .named(SidebarDragCoordinateSpace.name))]]
                )
            }
        }
        .overlay {
            if let headerFrame = geometry[.customSectionHeader(Self.sectionID)]?.sidebarUnion,
               let viewport = geometry[.viewport]?.sidebarUnion {
                GeometryReader { proxy in
                    sidebarSnapshotSectionContainerBorder(
                        frame: sidebarSectionContainerFrame(headerFrame: headerFrame, contentFrames: []),
                        viewport: viewport,
                        overlaySize: proxy.size
                    )
                }
            }
        }
        .onPreferenceChange(SidebarDragGeometryPreferenceKey.self) { frames in
            geometry = frames
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
