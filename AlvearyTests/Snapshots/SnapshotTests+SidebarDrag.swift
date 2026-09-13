import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarDragExpandedProjectFadesHeaderChildrenAndSelectedChrome() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()
        sidebar.activeThread.modifiedAt = Date(timeIntervalSince1970: 1_713_000_000)
        _ = try addSecondActiveThread(to: sidebar)
        let appState = AppState()
        appState.selectedSidebarItem = .thread(sidebar.activeThread)
        let item: SidebarDragItem = .project(sidebar.project.persistentModelID)
        let session = SidebarDragSession(
            id: UUID(), item: item, location: .zero,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: sidebar.pinnedThread.map { [.pinnedThread($0.persistentModelID)] } ?? [],
                regularProjects: [.project(sidebar.project.persistentModelID), .project(sidebar.emptyProject.persistentModelID)]
            )
        )
        let observation = SidebarDragSnapshotObservation()

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 540),
            named: "sidebar_drag_expanded_project_faded"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel, appState: appState,
                initialExpandedProjects: [sidebar.project.id], initialDragSession: session
            )
            .overlay(alignment: .topLeading) { SidebarDragSnapshotProbe(observation: observation).frame(width: 1, height: 1) }
        }
        XCTAssertEqual(observation.lastActiveItem, item, "The snapshot must retain the seeded production drag state")
        XCTAssertGreaterThan(observation.observationCount, 0)
    }

    func testSidebarDragStandalonePinnedThreadFadesCompleteRow() async throws {
        let sidebar = try await makeSidebarSnapshotFixture(includePinnedThread: true)
        let pinnedThread = try XCTUnwrap(sidebar.pinnedThread)
        let appState = AppState()
        appState.selectedSidebarItem = .thread(pinnedThread)
        let item: SidebarDragItem = .pinnedThread(pinnedThread.persistentModelID)
        let session = SidebarDragSession(
            id: UUID(), item: item, location: .zero,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: sidebar.pinnedThread.map { [.pinnedThread($0.persistentModelID)] } ?? [],
                regularProjects: [.project(sidebar.project.persistentModelID), .project(sidebar.emptyProject.persistentModelID)]
            )
        )
        let observation = SidebarDragSnapshotObservation()

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 540),
            named: "sidebar_drag_standalone_pinned_thread_faded"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel, appState: appState,
                initialExpandedProjects: [], initialDragSession: session
            )
            .overlay(alignment: .topLeading) { SidebarDragSnapshotProbe(observation: observation).frame(width: 1, height: 1) }
        }
        XCTAssertEqual(observation.lastActiveItem, item, "The snapshot must retain the seeded production drag state")
        XCTAssertGreaterThan(observation.observationCount, 0)
    }

    func testSidebarDragExpandedEmptyProjectFadesPlaceholder() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()
        let appState = AppState()
        appState.selectedSidebarItem = .project(sidebar.emptyProject)
        let item: SidebarDragItem = .project(sidebar.emptyProject.persistentModelID)
        let session = SidebarDragSession(
            id: UUID(), item: item, location: .zero,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: sidebar.pinnedThread.map { [.pinnedThread($0.persistentModelID)] } ?? [],
                regularProjects: [.project(sidebar.project.persistentModelID), .project(sidebar.emptyProject.persistentModelID)]
            )
        )
        let observation = SidebarDragSnapshotObservation()

        await assertMacModelSnapshot(
            modelContainer: sidebar.fixture.container,
            size: CGSize(width: 320, height: 540),
            named: "sidebar_drag_expanded_empty_project_faded"
        ) {
            SidebarView(
                viewModel: sidebar.fixture.viewModel, appState: appState,
                initialExpandedProjects: [sidebar.emptyProject.id], initialDragSession: session
            )
            .overlay(alignment: .topLeading) { SidebarDragSnapshotProbe(observation: observation).frame(width: 1, height: 1) }
        }
        XCTAssertEqual(observation.lastActiveItem, item, "The snapshot must retain the seeded production drag state")
        XCTAssertGreaterThan(observation.observationCount, 0)
    }

    func testSidebarDragInsertionIndicatorAppearsBelowExpandedProjectTerminalChild() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()
        let secondThread = try addSecondActiveThread(to: sidebar)

        assertMacSnapshot(
            SidebarTerminalDropIndicatorSnapshot(
                targetProject: sidebar.project,
                sourceProject: sidebar.emptyProject,
                threads: [sidebar.activeThread, secondThread]
            ),
            size: CGSize(width: 320, height: 210),
            named: "sidebar_drag_indicator_below_terminal_child"
        )
    }

    func testSidebarDragHiddenPinnedTargetAppearsAboveProjectsHeader() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        assertMacSnapshot(
            SidebarHiddenPinnedDropIndicatorSnapshot(
                targetProject: sidebar.project,
                sourceProject: sidebar.emptyProject
            ),
            size: CGSize(width: 320, height: 170),
            named: "sidebar_drag_hidden_pinned_target"
        )
    }

    private func addSecondActiveThread(to sidebar: SnapshotSidebarFixture) throws -> AgentThread {
        let thread = AgentThread(
            name: "Verify Sidebar Ordering",
            modifiedAt: Date(timeIntervalSince1970: 1_713_000_050),
            project: sidebar.project
        )
        let conversation = Conversation(
            id: "sidebar-drag-second-thread",
            title: "Main",
            provider: "claude",
            thread: thread
        )
        thread.conversations = [conversation]
        sidebar.project.threads.append(thread)
        sidebar.fixture.context.insert(thread)
        sidebar.fixture.context.insert(conversation)
        try sidebar.fixture.context.save()
        return thread
    }

}

@MainActor
private struct SidebarTerminalDropIndicatorSnapshot: View {
    let targetProject: Project
    let sourceProject: Project
    let threads: [AgentThread]

    var body: some View {
        List {
            projectRow(targetProject, isExpanded: true)

            ForEach(Array(threads.enumerated()), id: \.element.persistentModelID) { index, thread in
                threadRow(
                    thread,
                    status: index == 0 ? .busy : .stopped,
                    isSelected: index == 0,
                    topSpacing: index == 0 ? 0 : SidebarRowMetrics.interThreadRowSpacing,
                    snapshotBoundaryRole: index == threads.indices.last ? .terminal : nil
                )
            }

            fadedProjectRow(
                sourceProject,
                isExpanded: false,
                topSpacing: SidebarProjectListMetrics.subsequentProjectTopSpacing,
                snapshotBoundaryRole: .nextHeader
            )
        }
        .listStyle(.sidebar)
        .overlayPreferenceValue(SidebarSnapshotBoundaryPreferenceKey.self) { anchors in
            GeometryReader { proxy in
                if let terminalAnchor = anchors[.terminal],
                   let nextHeaderAnchor = anchors[.nextHeader] {
                    let terminalFrame = proxy[terminalAnchor]
                    let nextHeaderFrame = proxy[nextHeaderAnchor]

                    SidebarDropInsertionIndicator(
                        indicatorY: (terminalFrame.maxY + nextHeaderFrame.minY) / 2,
                        viewport: CGRect(origin: .zero, size: proxy.size),
                        overlaySize: proxy.size
                    )
                }
            }
            .allowsHitTesting(false)
        }
    }
}

@MainActor
private struct SidebarHiddenPinnedDropIndicatorSnapshot: View {
    let targetProject: Project
    let sourceProject: Project

    var body: some View {
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                SidebarSectionHeaderRow(title: "Projects", onAddProject: {})
                projectRow(targetProject, isExpanded: false)
                fadedProjectRow(
                    sourceProject,
                    isExpanded: false,
                    topSpacing: SidebarProjectListMetrics.subsequentProjectTopSpacing
                )

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 36)

            GeometryReader { proxy in
                SidebarDropInsertionIndicator(
                    indicatorY: 0,
                    viewport: CGRect(origin: .zero, size: proxy.size),
                    overlaySize: proxy.size
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}

private let sidebarDraggedRowOpacity = 0.48

private enum SidebarSnapshotBoundaryRole: Hashable {
    case terminal
    case nextHeader
}

private struct SidebarSnapshotBoundaryPreferenceKey: PreferenceKey {
    static let defaultValue: [SidebarSnapshotBoundaryRole: Anchor<CGRect>] = [:]

    static func reduce(
        value: inout [SidebarSnapshotBoundaryRole: Anchor<CGRect>],
        nextValue: () -> [SidebarSnapshotBoundaryRole: Anchor<CGRect>]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct SidebarSnapshotBoundaryAnchorModifier: ViewModifier {
    let role: SidebarSnapshotBoundaryRole?

    @ViewBuilder
    func body(content: Content) -> some View {
        if let role {
            content.anchorPreference(key: SidebarSnapshotBoundaryPreferenceKey.self, value: .bounds) { bounds in
                [role: bounds]
            }
        } else {
            content
        }
    }
}

@MainActor
private func fadedProjectRow(
    _ project: Project,
    isExpanded: Bool,
    isSelected: Bool = false,
    topSpacing: CGFloat = 0,
    snapshotBoundaryRole: SidebarSnapshotBoundaryRole? = nil
) -> some View {
    projectRow(
        project,
        isExpanded: isExpanded,
        isSelected: isSelected,
        suppressHoverAffordances: true,
        topSpacing: topSpacing,
        snapshotBoundaryRole: snapshotBoundaryRole
    )
    .opacity(sidebarDraggedRowOpacity)
    .appSelectionRowBackground(
        isSelected: isSelected,
        topInset: topSpacing,
        opacity: sidebarDraggedRowOpacity
    )
}

@MainActor
private func projectRow(
    _ project: Project,
    isExpanded: Bool,
    isSelected: Bool = false,
    suppressHoverAffordances: Bool = false,
    topSpacing: CGFloat = 0,
    snapshotBoundaryRole: SidebarSnapshotBoundaryRole? = nil
) -> some View {
    SidebarProjectRow(
        projectName: project.name,
        isExpanded: isExpanded,
        isSelected: isSelected,
        suppressHoverAffordances: suppressHoverAffordances,
        onToggleExpanded: {},
        onActivate: {},
        onCreateThread: {}
    )
    .modifier(SidebarSnapshotBoundaryAnchorModifier(role: snapshotBoundaryRole))
    .padding(.top, topSpacing)
}

@MainActor
private func threadRow(
    _ thread: AgentThread,
    status: ThreadStatus,
    isSelected: Bool,
    topSpacing: CGFloat,
    suppressHoverAffordances: Bool = false,
    snapshotBoundaryRole: SidebarSnapshotBoundaryRole? = nil
) -> some View {
    SidebarThreadRow(
        presentation: SidebarThreadRowPresentation(thread: thread),
        status: status,
        isSelected: isSelected,
        suppressHoverAffordances: suppressHoverAffordances,
        onCommitRename: { _ in }
    )
    .modifier(SidebarSnapshotBoundaryAnchorModifier(role: snapshotBoundaryRole))
    .padding(.leading, 14)
    .padding(.top, topSpacing)
}

@MainActor
private final class SidebarDragSnapshotObservation {
    var lastActiveItem: SidebarDragItem?
    var observationCount = 0
}

/// Physical pointer polling is irrelevant to a seeded visual fixture. Stop the mounted monitor's
/// timers while keeping the sidebar's real drag state and row rendering intact.
private struct SidebarDragSnapshotProbe: NSViewRepresentable {
    let observation: SidebarDragSnapshotObservation

    func makeNSView(context: Context) -> SidebarDragSnapshotProbeView {
        SidebarDragSnapshotProbeView(observation: observation)
    }

    func updateNSView(_ view: SidebarDragSnapshotProbeView, context: Context) { view.observeDrag() }
}

private final class SidebarDragSnapshotProbeView: NSView {
    let observation: SidebarDragSnapshotObservation

    init(observation: SidebarDragSnapshotObservation) {
        self.observation = observation
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { return nil }

    override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); observeDrag() }
    override func layout() { super.layout(); observeDrag() }
    override func draw(_ dirtyRect: NSRect) { observeDrag() }

    func observeDrag() {
        guard let root = window?.contentView, let monitor = dragMonitor(in: root) else { return }
        monitor.stopEscapeWatch()
        monitor.stopAutoscroll()
        observation.observationCount += 1
        if case .active(let session) = monitor.interactionState {
            observation.lastActiveItem = session.item
        } else {
            observation.lastActiveItem = nil
        }
    }

    private func dragMonitor(in view: NSView) -> SidebarDragMonitorView? {
        if let monitor = view as? SidebarDragMonitorView { return monitor }
        return view.subviews.lazy.compactMap { self.dragMonitor(in: $0) }.first
    }
}
