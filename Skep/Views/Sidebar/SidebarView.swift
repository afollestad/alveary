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
                        ProjectRow(
                            project: project,
                            isExpanded: expandedProjects.contains(project.path),
                            onToggleExpanded: {
                                toggleExpansion(for: project.path, in: &expandedProjects)
                            },
                            onCreateThread: {
                                Task { await createThread(in: project) }
                            }
                        )
                        .tag(SidebarItem.project(project))

                        if expandedProjects.contains(project.path) {
                            ForEach(activeThreads(for: project)) { thread in
                                ThreadRow(thread: thread, status: viewModel.threadStatus(for: thread))
                                    .tag(SidebarItem.thread(thread))
                                    .padding(.leading, 18)
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
                                ArchivedThreadsRow(
                                    isExpanded: expandedArchivedProjects.contains(project.path),
                                    onToggle: {
                                        toggleExpansion(for: project.path, in: &expandedArchivedProjects)
                                    }
                                )
                                .padding(.leading, 18)

                                if expandedArchivedProjects.contains(project.path) {
                                    ForEach(archivedThreads) { thread in
                                        ThreadRow(thread: thread, status: .archived)
                                            .padding(.leading, 18)
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
                    ProjectsHeaderRow {
                        appState.openNewProjectFlow()
                    }
                }
            }
            .listStyle(.sidebar)
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

private struct ProjectsHeaderRow: View {
    let onAddProject: () -> Void

    var body: some View {
        HStack {
            Text("Projects")
                .font(.headline)
                .foregroundStyle(.primary)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button(action: onAddProject) {
                Image(systemName: "plus.circle")
                    .frame(width: 16)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Add Project")
            .help("Add Project")
        }
        .padding(.leading, 8)
        .padding(.trailing, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }
}

private struct ProjectRow: View {
    let project: Project
    let isExpanded: Bool
    let onToggleExpanded: () -> Void
    let onCreateThread: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onToggleExpanded) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Image(systemName: "folder")
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(project.name)
                    .font(.headline)

                Text(project.baseRef ?? project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Button(action: onCreateThread) {
                Image(systemName: "square.and.pencil")
            }
            .buttonStyle(.borderless)
            .help("New Thread")
        }
        .padding(.vertical, 4)
    }
}

private struct ThreadRow: View {
    let thread: AgentThread
    let status: ThreadStatus

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
                .opacity(status == .stopped ? 0 : 1)

            VStack(alignment: .leading, spacing: 2) {
                Text(thread.name)
                    .lineLimit(1)

                if let branch = thread.branch {
                    Text(branch)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
    }

    private var statusColor: Color {
        switch status {
        case .busy:
            return .green
        case .idle:
            return .blue
        case .error:
            return .red
        case .archived:
            return .secondary
        case .stopped:
            return .clear
        }
    }
}

private struct ArchivedThreadsRow: View {
    let isExpanded: Bool
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 10) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .frame(width: 12)

                Label("Archived", systemImage: "archivebox")
                    .foregroundStyle(.secondary)

                Spacer()
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }
}
