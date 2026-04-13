import SwiftData
import SwiftUI

struct SidebarView: View {
    let viewModel: SidebarViewModel
    @Bindable var appState: AppState

    @Environment(\.modelContext) private var uiModelContext
    @Query private var queriedProjects: [Project]
    @State private var expandedProjects: Set<String> = []
    @State private var expandedArchivedProjects: Set<String> = []
    @State private var pendingDeleteThread: AgentThread?
    @State private var pendingDeleteProject: Project?

    private var projects: [Project] {
        queriedProjects.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let statusVersion = viewModel.statusVersion

        return VStack(spacing: 0) {
            if let sidebarError = viewModel.sidebarError {
                InlineBanner(message: sidebarError, severity: .error, autoDismissAfter: nil) {
                    viewModel.dismissSidebarError()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }

            List {
                Section {
                    topLevelRow(
                        title: "Skills",
                        systemImage: "puzzlepiece.extension",
                        item: .skills
                    )

                    topLevelRow(
                        title: "MCP",
                        systemImage: "server.rack",
                        item: .mcp
                    )
                }

                Section {
                    if projects.isEmpty {
                        Text("No projects yet")
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }

                    ForEach(projects.indices, id: \.self) { index in
                        let project = projects[index]
                        let isExpanded = expandedProjects.contains(project.path)
                        let isArchivedExpanded = expandedArchivedProjects.contains(project.path)
                        let activeProjectThreads = activeThreads(for: project)
                        let archivedProjectThreads = archivedThreads(for: project)
                        let projectTopSpacing = spacingBeforeProject(at: index, in: projects)

                        SidebarProjectRow(
                            project: project,
                            isExpanded: isExpanded,
                            isSelected: appState.selectedSidebarItem == .project(project),
                            onToggleExpanded: {
                                toggleExpansion(for: project.path, in: &expandedProjects)
                            },
                            onActivate: {
                                activateProject(project)
                            },
                            onCreateThread: {
                                Task { await createThread(in: project) }
                            }
                        )
                        .appSelectionRowBackground(
                            isSelected: appState.selectedSidebarItem == .project(project),
                            topInset: projectTopSpacing
                        )
                        .padding(.top, projectTopSpacing)
                        .contextMenu {
                            Button("New Thread") {
                                Task { await createThread(in: project) }
                            }

                            Button("Remove Project...", role: .destructive) {
                                pendingDeleteProject = project
                            }
                        }

                        if isExpanded {
                            ForEach(activeProjectThreads.indices, id: \.self) { index in
                                let thread = activeProjectThreads[index]

                                SidebarThreadRow(
                                    thread: thread,
                                    status: viewModel.threadStatus(for: thread),
                                    isSelected: appState.selectedSidebarItem == .thread(thread),
                                    onActivate: {
                                        activateThread(thread)
                                    }
                                )
                                    .padding(.leading, 14)
                                    .appSelectionRowBackground(isSelected: appState.selectedSidebarItem == .thread(thread))
                                    .contextMenu {
                                        Button("Archive") {
                                            Task { await archive(thread) }
                                        }

                                        Button("Delete", role: .destructive) {
                                            pendingDeleteThread = thread
                                        }
                                    }
                            }

                            if !archivedProjectThreads.isEmpty {
                                SidebarArchivedThreadsRow(
                                    isExpanded: isArchivedExpanded,
                                    onToggle: {
                                        toggleExpansion(for: project.path, in: &expandedArchivedProjects)
                                    }
                                )
                                .padding(.leading, 14)

                                if isArchivedExpanded {
                                    ForEach(archivedProjectThreads.indices, id: \.self) { index in
                                        let thread = archivedProjectThreads[index]

                                        SidebarThreadRow(
                                            thread: thread,
                                            status: .archived,
                                            isSelected: appState.selectedSidebarItem == .thread(thread),
                                            onActivate: {
                                                activateThread(thread)
                                            }
                                        )
                                            .padding(.leading, 14)
                                            .appSelectionRowBackground(isSelected: appState.selectedSidebarItem == .thread(thread))
                                            .opacity(0.75)
                                            .contextMenu {
                                                Button("Restore") {
                                                    Task { await restore(thread, in: project) }
                                                }

                                                Button("Delete", role: .destructive) {
                                                    pendingDeleteThread = thread
                                                }
                                            }
                                    }
                                }
                            }
                        }
                    }
                } header: {
                    SidebarProjectsHeaderRow {
                        appState.openNewProjectFlow()
                    }
                }
            }
            .listStyle(.sidebar)
            .onKeyPress(keys: [.leftArrow, .rightArrow], action: handleSidebarKeyPress)
        }
        .onAppear {
            syncExpansionWithSelection(appState.selectedSidebarItem)
        }
        .onChange(of: appState.selectedSidebarItem) { _, item in
            syncExpansionWithSelection(item)
        }
        .animation(nil, value: statusVersion)
        .confirmationDialog(
            "Delete thread?",
            isPresented: Binding(
                get: { pendingDeleteThread != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteThread = nil
                    }
                }
            ),
            presenting: pendingDeleteThread
        ) { thread in
            Button("Delete", role: .destructive) {
                Task { await confirmDeleteThread(thread) }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteThread = nil
            }
        } message: { thread in
            Text("This permanently deletes \(thread.name) and removes its worktree and branch if present.")
        }
        .alert(
            "Remove project?",
            isPresented: Binding(
                get: { pendingDeleteProject != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingDeleteProject = nil
                    }
                }
            ),
            presenting: pendingDeleteProject
        ) { project in
            Button("Remove Project", role: .destructive) {
                Task { await confirmDeleteProject(project) }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteProject = nil
            }
        } message: { project in
            Text(
                "Remove \(project.name) from Alveary, and delete its threads and worktrees? " +
                    "The main project folder will not be touched."
            )
        }
    }
}

private extension SidebarView {
    func spacingBeforeProject(at index: Int, in projects: [Project]) -> CGFloat {
        guard index > 0 else {
            return 0
        }

        let previousProject = projects[index - 1]
        let previousActiveThreads = activeThreads(for: previousProject)
        let previousArchivedThreads = archivedThreads(for: previousProject)
        let hasExpandedContent = !previousActiveThreads.isEmpty || !previousArchivedThreads.isEmpty

        guard expandedProjects.contains(previousProject.path), hasExpandedContent else {
            return 0
        }

        return 8
    }

    func topLevelRow(title: String, systemImage: String, item: SidebarItem) -> some View {
        Button {
            appState.selectedSidebarItem = item
        } label: {
            Label(title, systemImage: systemImage)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(appState.selectedSidebarItem == item ? .isSelected : [])
        .appSelectionRowBackground(isSelected: appState.selectedSidebarItem == item)
    }

    func activeThreads(for project: Project) -> [AgentThread] {
        project.threads
            .filter { $0.archivedAt == nil }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func archivedThreads(for project: Project) -> [AgentThread] {
        project.threads
            .filter { $0.archivedAt != nil }
            .sorted { lhs, rhs in
                let leftDate = lhs.archivedAt ?? .distantPast
                let rightDate = rhs.archivedAt ?? .distantPast
                return leftDate > rightDate
            }
    }

    func toggleExpansion(for path: String, in set: inout Set<String>) {
        if set.contains(path) {
            set.remove(path)
        } else {
            set.insert(path)
        }
    }

    func activateProject(_ project: Project) {
        let item = SidebarItem.project(project)
        if appState.selectedSidebarItem == item {
            toggleExpansion(for: project.path, in: &expandedProjects)
        } else {
            appState.selectedSidebarItem = item
        }
    }

    func activateThread(_ thread: AgentThread) {
        appState.selectedSidebarItem = .thread(thread)
    }

    func handleSidebarKeyPress(_ keyPress: KeyPress) -> KeyPress.Result {
        guard case .project(let project) = appState.selectedSidebarItem else {
            return .ignored
        }

        switch keyPress.key {
        case .leftArrow:
            expandedProjects.remove(project.path)
            return .handled
        case .rightArrow:
            expandedProjects.insert(project.path)
            return .handled
        default:
            return .ignored
        }
    }

    func syncExpansionWithSelection(_ item: SidebarItem?) {
        switch item {
        case .project(let project):
            expandedProjects.insert(project.path)
        case .thread(let thread):
            if let projectPath = thread.project?.path {
                expandedProjects.insert(projectPath)
            }
        default:
            break
        }
    }

    func createThread(in project: Project) async {
        do {
            let createdThread = try await viewModel.createThread(project: project)
            guard let resolvedThread = resolveThread(id: createdThread.persistentModelID) else {
                return
            }

            expandedProjects.insert(project.path)
            appState.selectedSidebarItem = .thread(resolvedThread)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func archive(_ thread: AgentThread) async {
        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection

        if case .thread(let selectedThread) = appState.selectedSidebarItem,
           selectedThread.persistentModelID == thread.persistentModelID,
           let project = thread.project {
            appState.selectedSidebarItem = .project(project)
        }

        if case .threadId(let bookmarkedID) = appState.previousSelection,
           bookmarkedID == thread.persistentModelID,
           let project = thread.project {
            appState.previousSelection = .projectPath(project.path)
        }

        do {
            try await viewModel.archiveThread(thread)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            viewModel.presentSidebarError(error)
        }
    }

    func restore(_ thread: AgentThread, in project: Project) async {
        do {
            try viewModel.restoreThread(thread)
            expandedProjects.insert(project.path)
        } catch {
            viewModel.presentSidebarError(error)
        }
    }

    func confirmDeleteThread(_ thread: AgentThread) async {
        pendingDeleteThread = nil

        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection

        if case .thread(let selectedThread) = appState.selectedSidebarItem,
           selectedThread.persistentModelID == thread.persistentModelID {
            appState.selectedSidebarItem = thread.project.map(SidebarItem.project)
        }

        if case .threadId(let bookmarkedID) = appState.previousSelection,
           bookmarkedID == thread.persistentModelID,
           let project = thread.project {
            appState.previousSelection = .projectPath(project.path)
        }

        do {
            try await viewModel.deleteThread(thread)
            appState.selectedConversationIDs.removeValue(forKey: thread.persistentModelID)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            viewModel.presentSidebarError(error)
        }
    }

    func confirmDeleteProject(_ project: Project) async {
        pendingDeleteProject = nil

        let previousSelectedItem = appState.selectedSidebarItem
        let previousBookmark = appState.previousSelection
        let previousConversationIDs = appState.selectedConversationIDs
        let previousDiffAction = appState.pendingDiffAction

        let threadIDs = Set(project.threads.map(\.persistentModelID))
        let conversationIDs = Set(project.threads.flatMap(\.conversations).map(\.persistentModelID))

        switch appState.selectedSidebarItem {
        case .project(let selectedProject) where selectedProject.path == project.path:
            appState.selectedSidebarItem = nil
        case .thread(let selectedThread) where threadIDs.contains(selectedThread.persistentModelID):
            appState.selectedSidebarItem = nil
        default:
            break
        }

        switch appState.previousSelection {
        case .projectPath(let projectPath) where projectPath == project.path:
            appState.previousSelection = nil
        case .threadId(let threadID) where threadIDs.contains(threadID):
            appState.previousSelection = nil
        default:
            break
        }

        for threadID in threadIDs {
            appState.selectedConversationIDs.removeValue(forKey: threadID)
        }

        if let pendingDiffAction = appState.pendingDiffAction,
           conversationIDs.contains(pendingDiffAction.conversationID) {
            appState.pendingDiffAction = nil
        }

        do {
            try await viewModel.deleteProject(project)
            expandedProjects.remove(project.path)
            expandedArchivedProjects.remove(project.path)
        } catch {
            appState.selectedSidebarItem = previousSelectedItem
            appState.previousSelection = previousBookmark
            appState.selectedConversationIDs = previousConversationIDs
            appState.pendingDiffAction = previousDiffAction
            viewModel.presentSidebarError(error)
        }
    }

    func resolveThread(id: PersistentIdentifier) -> AgentThread? {
        uiModelContext.model(for: id) as? AgentThread
    }
}
