import SwiftData
import SwiftUI
import XCTest

@testable import Alveary

extension SnapshotTests {
    func testSidebarDragExpandedProjectFadesHeaderChildrenAndSelectedChrome() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()
        let secondThread = try addSecondActiveThread(to: sidebar)

        assertMacSnapshot(
            SidebarDraggedProjectGroupSnapshot(
                project: sidebar.project,
                threads: [secondThread, sidebar.activeThread],
                selectedThreadID: sidebar.activeThread.persistentModelID
            ),
            size: CGSize(width: 320, height: 170),
            named: "sidebar_drag_expanded_project_faded"
        )
    }

    func testSidebarDragStandalonePinnedThreadFadesCompleteRow() async throws {
        let sidebar = try await makeSidebarSnapshotFixture(includePinnedThread: true)
        let pinnedThread = try XCTUnwrap(sidebar.pinnedThread)

        assertMacSnapshot(
            SidebarDraggedPinnedThreadSnapshot(thread: pinnedThread),
            size: CGSize(width: 320, height: 140),
            named: "sidebar_drag_standalone_pinned_thread_faded"
        )
    }

    func testSidebarDragExpandedEmptyProjectFadesPlaceholder() async throws {
        let sidebar = try await makeSidebarSnapshotFixture()

        assertMacSnapshot(
            SidebarDraggedEmptyProjectSnapshot(project: sidebar.emptyProject),
            size: CGSize(width: 320, height: 140),
            named: "sidebar_drag_expanded_empty_project_faded"
        )
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

    func testSidebarProjectDragShowsNoIndicatorBetweenConsecutivePinnedThreads() async throws {
        let sidebar = try await makeSidebarSnapshotFixture(includePinnedThread: true)
        let firstThread = try XCTUnwrap(sidebar.pinnedThread)
        let secondThread = try addSecondPinnedThread(to: sidebar)
        let sourceItem = SidebarDragItem.project(sidebar.emptyProject.persistentModelID)
        let geometry: [SidebarDragGeometryRole: [CGRect]] = [
            .viewport: [CGRect(x: 0, y: 0, width: 320, height: 240)],
            .pinnedThread(firstThread.persistentModelID): [CGRect(x: 0, y: 40, width: 320, height: 32)],
            .pinnedThread(secondThread.persistentModelID): [CGRect(x: 0, y: 74, width: 320, height: 32)],
            .projectsHeader: [CGRect(x: 0, y: 130, width: 320, height: 32)]
        ]
        let candidate = sidebarDropCandidateForLocation(
            at: CGPoint(x: 160, y: 73),
            dragging: sourceItem,
            geometry: geometry,
            logicalOrder: SidebarDragLogicalOrder(
                pinnedItems: [
                    .pinnedThread(firstThread.persistentModelID),
                    .pinnedThread(secondThread.persistentModelID)
                ],
                regularProjects: [sourceItem, .project(sidebar.project.persistentModelID)],
                projectsHeaderIsSticky: false
            )
        )

        assertMacSnapshot(
            SidebarPinnedThreadBoundarySnapshot(
                firstThread: firstThread,
                secondThread: secondThread,
                sourceProject: sidebar.emptyProject,
                showsInvalidProjectIndicator: candidate != nil
            ),
            size: CGSize(width: 320, height: 250),
            named: "sidebar_project_drag_no_indicator_between_pinned_threads"
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

    private func addSecondPinnedThread(to sidebar: SnapshotSidebarFixture) throws -> AgentThread {
        let thread = AgentThread(
            name: "Audit Drag Boundaries",
            isPinned: true,
            modifiedAt: Date(timeIntervalSince1970: 1_713_000_075),
            project: sidebar.project
        )
        let conversation = Conversation(
            id: "sidebar-drag-second-pinned-thread",
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
private struct SidebarDraggedProjectGroupSnapshot: View {
    let project: Project
    let threads: [AgentThread]
    let selectedThreadID: PersistentIdentifier

    var body: some View {
        List {
            fadedProjectRow(project, isExpanded: true)

            ForEach(Array(threads.enumerated()), id: \.element.persistentModelID) { index, thread in
                fadedThreadRow(
                    thread,
                    status: index == 0 ? .stopped : .busy,
                    isSelected: thread.persistentModelID == selectedThreadID,
                    topSpacing: index == 0 ? 0 : SidebarRowMetrics.interThreadRowSpacing
                )
            }
        }
        .listStyle(.sidebar)
    }
}

@MainActor
private struct SidebarDraggedPinnedThreadSnapshot: View {
    let thread: AgentThread

    var body: some View {
        List {
            SidebarSectionHeaderRow(title: "Pinned")

            SidebarThreadRow(
                thread: thread,
                status: .waitingForUser,
                isSelected: true,
                layout: .topLevel,
                editingThreadID: .constant(nil),
                suppressHoverAffordances: true,
                onCommitRename: { _ in }
            )
            .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding)
            .opacity(sidebarDraggedRowOpacity)
            .appSelectableRow(
                isSelected: true,
                selectionBackgroundOpacity: sidebarDraggedRowOpacity,
                suppressesPressFeedback: true,
                suppressesAction: true,
                action: {}
            )
        }
        .listStyle(.sidebar)
    }
}

@MainActor
private struct SidebarDraggedEmptyProjectSnapshot: View {
    let project: Project

    var body: some View {
        List {
            fadedProjectRow(project, isExpanded: true, isSelected: true)

            Text("No threads")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 6.75)
                .padding(.leading, SidebarProjectRow.projectNameLeadingInset)
                .opacity(sidebarDraggedRowOpacity)
        }
        .listStyle(.sidebar)
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

                    sidebarDropInsertionIndicator
                        .position(
                            x: proxy.size.width / 2,
                            y: (terminalFrame.maxY + nextHeaderFrame.minY) / 2
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

            sidebarDropInsertionIndicator
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .clipped()
    }
}

@MainActor
private struct SidebarPinnedThreadBoundarySnapshot: View {
    let firstThread: AgentThread
    let secondThread: AgentThread
    let sourceProject: Project
    let showsInvalidProjectIndicator: Bool

    var body: some View {
        List {
            SidebarSectionHeaderRow(title: "Pinned")

            topLevelThreadRow(firstThread, status: .waitingForUser)
                .overlay(alignment: .bottom) {
                    if showsInvalidProjectIndicator {
                        sidebarDropInsertionIndicator
                    }
                }

            topLevelThreadRow(
                secondThread,
                status: .stopped,
                topSpacing: SidebarRowMetrics.interThreadRowSpacing
            )

            SidebarSectionHeaderRow(title: "Projects", onAddProject: {})
            fadedProjectRow(sourceProject, isExpanded: false)
        }
        .listStyle(.sidebar)
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
private var sidebarDropInsertionIndicator: some View {
    Rectangle()
        .fill(AppAccentFill.primary)
        .frame(width: 300, height: 2)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
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
        project: project,
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
private func fadedThreadRow(
    _ thread: AgentThread,
    status: ThreadStatus,
    isSelected: Bool,
    topSpacing: CGFloat
) -> some View {
    threadRow(
        thread,
        status: status,
        isSelected: isSelected,
        topSpacing: topSpacing,
        suppressHoverAffordances: true
    )
    .opacity(sidebarDraggedRowOpacity)
    .appSelectableRow(
        isSelected: isSelected,
        selectionBackgroundTopInset: topSpacing,
        selectionBackgroundOpacity: sidebarDraggedRowOpacity,
        suppressesPressFeedback: true,
        suppressesAction: true,
        action: {}
    )
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
        thread: thread,
        status: status,
        isSelected: isSelected,
        editingThreadID: .constant(nil),
        suppressHoverAffordances: suppressHoverAffordances,
        onCommitRename: { _ in }
    )
    .modifier(SidebarSnapshotBoundaryAnchorModifier(role: snapshotBoundaryRole))
    .padding(.leading, 14)
    .padding(.top, topSpacing)
}

@MainActor
private func topLevelThreadRow(
    _ thread: AgentThread,
    status: ThreadStatus,
    topSpacing: CGFloat = 0
) -> some View {
    SidebarThreadRow(
        thread: thread,
        status: status,
        isSelected: false,
        layout: .topLevel,
        editingThreadID: .constant(nil),
        suppressHoverAffordances: true,
        onCommitRename: { _ in }
    )
    .padding(.leading, SidebarSectionHeaderRow.contentLeadingPadding)
    .padding(.top, topSpacing)
    .appSelectableRow(
        isSelected: false,
        selectionBackgroundTopInset: topSpacing,
        suppressesPressFeedback: true,
        suppressesAction: true,
        action: {}
    )
}
