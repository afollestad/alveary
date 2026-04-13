import SwiftData
import SwiftUI

struct SidebarView: View {
    let viewModel: SidebarViewModel
    @Bindable var appState: AppState

    @Environment(\.modelContext) var uiModelContext
    @Query private var queriedProjects: [Project]
    @State var expandedProjects: Set<String> = []
    @State private var editingThreadID: PersistentIdentifier?
    @State var pendingArchiveThread: AgentThread?
    @State var pendingDeleteThread: AgentThread?
    @State var pendingDeleteProject: Project?

    var projects: [Project] {
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
                        let activeProjectThreads = activeThreads(for: project)
                        let projectTopSpacing = spacingBeforeProject(at: index, in: projects)

                        let isProjectActive: Bool = switch appState.selectedSidebarItem {
                        case .project(let selected) where selected.path == project.path: true
                        case .thread(let thread) where thread.project?.path == project.path: true
                        default: false
                        }

                        SidebarProjectRow(
                            project: project,
                            isExpanded: isExpanded,
                            isSelected: appState.selectedSidebarItem == .project(project),
                            isActive: isProjectActive,
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
                            ForEach(activeProjectThreads, id: \.persistentModelID) { thread in
                                SidebarThreadRow(
                                    thread: thread,
                                    status: viewModel.threadStatus(for: thread),
                                    editingThreadID: $editingThreadID,
                                    onCommitRename: { newName in
                                        renameThread(thread, to: newName)
                                    }
                                )
                                    .padding(.leading, 14)
                                    .appSelectableRow(
                                        isSelected: appState.selectedSidebarItem == .thread(thread),
                                        action: { activateThread(thread) }
                                    )
                                    .contextMenu {
                                        Button("Archive...") {
                                            pendingArchiveThread = thread
                                        }

                                        Button("Rename") {
                                            editingThreadID = thread.persistentModelID
                                        }

                                        Button("Delete...", role: .destructive) {
                                            pendingDeleteThread = thread
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
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, Self.backspaceKey], action: handleSidebarKeyPress)
        }
        .onAppear {
            syncExpansionWithSelection(appState.selectedSidebarItem)
        }
        .onChange(of: appState.selectedSidebarItem) { _, item in
            syncExpansionWithSelection(item)
        }
        .animation(nil, value: statusVersion)
        .confirmationDialog(
            "Archive thread?",
            isPresented: Binding(
                get: { pendingArchiveThread != nil },
                set: { isPresented in
                    if !isPresented {
                        pendingArchiveThread = nil
                    }
                }
            ),
            presenting: pendingArchiveThread
        ) { thread in
            Button("Archive") {
                pendingArchiveThread = nil
                Task { await archive(thread) }
            }

            Button("Cancel", role: .cancel) {
                pendingArchiveThread = nil
            }
        } message: { thread in
            Text(archiveConfirmationMessage(for: thread))
        }
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
            Text(deleteConfirmationMessage(for: thread))
        }
        .confirmationDialog(
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

    func archiveConfirmationMessage(for thread: AgentThread) -> String {
        "This archives \"\(thread.displayName())\". "
            + "You can find archived threads in the selected project's settings, at the bottom under Archived Threads."
    }

    func deleteConfirmationMessage(for thread: AgentThread) -> String {
        "This permanently deletes \"\(thread.displayName())\" and removes its worktree and branch if present."
    }
}
