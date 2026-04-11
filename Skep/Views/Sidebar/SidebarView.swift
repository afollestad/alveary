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

            List(selection: $appState.selectedSidebarItem) {
                Section {
                    Label("Skills", systemImage: "puzzlepiece.extension")
                        .tag(SidebarItem.skills)

                    Label("MCP", systemImage: "server.rack")
                        .tag(SidebarItem.mcp)
                }

                Section {
                    if projects.isEmpty {
                        Text("No projects yet")
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                    }

                    ForEach(projects) { project in
                        SidebarProjectRow(
                            project: project,
                            isExpanded: expandedProjects.contains(project.path),
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
                        .tag(SidebarItem.project(project))

                        if expandedProjects.contains(project.path) {
                            ForEach(activeThreads(for: project)) { thread in
                                SidebarThreadRow(thread: thread, status: viewModel.threadStatus(for: thread))
                                    .tag(SidebarItem.thread(thread))
                                    .padding(.leading, 14)
                                    .contextMenu {
                                        Button("Archive") {
                                            Task { await archive(thread) }
                                        }

                                        Button("Delete", role: .destructive) {
                                            pendingDeleteThread = thread
                                        }
                                    }
                            }

                            let archivedThreads = archivedThreads(for: project)
                            if !archivedThreads.isEmpty {
                                SidebarArchivedThreadsRow(
                                    isExpanded: expandedArchivedProjects.contains(project.path),
                                    onToggle: {
                                        toggleExpansion(for: project.path, in: &expandedArchivedProjects)
                                    }
                                )
                                .padding(.leading, 14)

                                if expandedArchivedProjects.contains(project.path) {
                                    ForEach(archivedThreads) { thread in
                                        SidebarThreadRow(thread: thread, status: .archived)
                                            .padding(.leading, 14)
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
                Task { await confirmDelete(thread) }
            }

            Button("Cancel", role: .cancel) {
                pendingDeleteThread = nil
            }
        } message: { thread in
            Text("This permanently deletes \(thread.name) and removes its worktree and branch if present.")
        }
    }
}

private extension SidebarView {
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

    func confirmDelete(_ thread: AgentThread) async {
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

    func resolveThread(id: PersistentIdentifier) -> AgentThread? {
        uiModelContext.model(for: id) as? AgentThread
    }
}
