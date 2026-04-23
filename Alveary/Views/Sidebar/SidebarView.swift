import SwiftData
import SwiftUI

struct SidebarView: View {
    let viewModel: SidebarViewModel
    @Bindable var appState: AppState

    @Environment(\.modelContext) var uiModelContext
    @Query private var queriedProjects: [Project]
    @State var expandedProjects: Set<String> = []
    @State var editingThreadID: PersistentIdentifier?
    @State var pendingArchiveThread: AgentThread?
    @State var pendingDeleteThread: AgentThread?
    @State var pendingDeleteProject: Project?
    @FocusState var isKeyboardFocused: Bool
    @FocusedValue(\.chatComposerFocus) var chatComposerFocus

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

                        SidebarProjectRow(
                            project: project,
                            isExpanded: isExpanded,
                            isSelected: appState.selectedSidebarItem == .project(project),
                            onToggleExpanded: {
                                toggleExpansion(for: project.path, in: &expandedProjects)
                                claimSidebarFocus()
                            },
                            onActivate: {
                                activateProject(project)
                            },
                            onCreateThread: {
                                Task { await createThread(in: project) }
                            }
                        )
                        .appSelectionRowBackground(
                            isSelected: appState.selectedSidebarItem == .project(project)
                        )
                        .contextMenu {
                            Button("New Thread") {
                                Task { await createThread(in: project) }
                            }

                            Button("Remove Project...", role: .destructive) {
                                pendingDeleteProject = project
                            }
                        }

                        if isExpanded {
                            if activeProjectThreads.isEmpty {
                                Text("No threads")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.vertical, 6.75)
                                    .padding(.leading, SidebarProjectRow.projectNameLeadingInset)
                                    .allowsHitTesting(false)
                            }

                            ForEach(activeProjectThreads, id: \.persistentModelID) { thread in
                                let isSelected = appState.selectedSidebarItem == .thread(thread)
                                SidebarThreadRow(
                                    thread: thread,
                                    status: viewModel.threadStatus(for: thread),
                                    isSelected: isSelected,
                                    editingThreadID: $editingThreadID,
                                    onCommitRename: { newName in
                                        renameThread(thread, to: newName)
                                    }
                                )
                                    .padding(.leading, 14)
                                    .appSelectableRow(
                                        isSelected: isSelected,
                                        action: { activateThread(thread) }
                                    )
                                    .contextMenu {
                                        Button("Archive...") {
                                            pendingArchiveThread = thread
                                        }

                                        // Hide "Rename..." when *any* row is being edited. Swapping
                                        // `editingThreadID` directly from one row to another left
                                        // the target row stuck "in editing state without an input
                                        // field" — the simultaneous unmount of A's TextField and
                                        // mount of B's within a single SwiftUI update pass didn't
                                        // converge. Force users to finish the in-flight rename first,
                                        // matching the invariant the keyboard rename already enforces
                                        // in `renameThreadID(for:editingThreadID:)`
                                        // (`SidebarView+KeyboardNavigation.swift`).
                                        if editingThreadID == nil {
                                            Button("Rename...") {
                                                editingThreadID = thread.persistentModelID
                                            }
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
            .focusable()
            .focused($isKeyboardFocused)
            .focusEffectDisabled()
            .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow, .return, Self.backspaceKey], action: handleSidebarKeyPress)
        }
        .onAppear {
            syncExpansionWithSelection(appState.selectedSidebarItem)
        }
        .onChange(of: appState.selectedSidebarItem) { _, item in
            syncExpansionWithSelection(item)
            // Skip the focus claim when a command has requested the composer grab focus
            // (e.g. ⌘N). `ChatInputField` consumes and clears the token once it focuses.
            if appState.pendingComposerFocusToken == nil {
                claimSidebarFocus()
            }
        }
        .onChange(of: appState.pendingComposerFocusToken) { _, token in
            // Release the sidebar's `@FocusState` claim so the composer can take AppKit
            // first responder without a fight. Without this, a sidebar that already holds
            // `isKeyboardFocused = true` (from prior keyboard navigation) keeps reclaiming
            // AppKit focus via `.focused($isKeyboardFocused)` while the composer tries to
            // take over.
            if token != nil {
                isKeyboardFocused = false
            }
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

    // Driven by explicit user actions (row tap, selection change, expansion toggle),
    // not by `.onChange(of: isKeyboardFocused)`. The reactive change handler also fires
    // when SwiftUI's `.focused($isKeyboardFocused)` re-claims the List after another
    // view briefly takes focus, which would yank focus back from the composer the
    // moment the user clicks into it.
    //
    // Always call this from row taps too — clicking the *already-selected* row does
    // not mutate `selectedSidebarItem`, so the `.onChange` hook never fires and the
    // composer would otherwise keep AppKit first-responder while the user expects
    // arrow keys to drive the sidebar.
    //
    // Clears `pendingComposerFocusToken` up front so a racing sidebar takeover
    // cancels an unconsumed composer-focus request. Without this, a user who presses
    // ⌘N and immediately clicks a different sidebar row before the new composer
    // mounts would see that composer steal first responder back once it mounts and
    // consumes the stale token.
    func claimSidebarFocus() {
        appState.pendingComposerFocusToken = nil
        chatComposerFocus?.wrappedValue = false
        isKeyboardFocused = true
    }
}
