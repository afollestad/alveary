import Foundation
import SwiftUI

struct EmptyThreadProjectOption {
    let project: Project
    let showsDisambiguatingPath: Bool
    let isSelected: Bool

    var displayPath: String {
        (project.path as NSString).abbreviatingWithTildeInPath
    }
}

@MainActor
func emptyThreadProjectOptions(
    projects: [Project],
    selectedProjectID: String?
) -> [EmptyThreadProjectOption] {
    let sortedProjects = projects.sorted { lhs, rhs in
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.id < rhs.id
    }

    return sortedProjects.map { project in
        EmptyThreadProjectOption(
            project: project,
            showsDisambiguatingPath: sortedProjects.contains { candidate in
                candidate.persistentModelID != project.persistentModelID &&
                    candidate.name.localizedCaseInsensitiveCompare(project.name) == .orderedSame
            },
            isSelected: project.id == selectedProjectID
        )
    }
}

struct EmptyThreadState: View {
    let setupPhase: SetupPhase?
    let isCancellingInitialSetup: Bool
    let thread: AgentThread?
    let projects: [Project]
    let isProjectSelectionDisabled: Bool
    let onSelectDestination: (ThreadDraftDestination) -> Void
    let sections: [SidebarSection]
    let workspaceConfiguration: ChatComposerActionRowView.TaskWorkspaceConfiguration?

    init(
        setupPhase: SetupPhase?,
        isCancellingInitialSetup: Bool,
        thread: AgentThread? = nil,
        projects: [Project] = [],
        sections: [SidebarSection] = [],
        isProjectSelectionDisabled: Bool = false,
        onSelectDestination: @escaping (ThreadDraftDestination) -> Void = { _ in },
        workspaceConfiguration: ChatComposerActionRowView.TaskWorkspaceConfiguration? = nil
    ) {
        self.setupPhase = setupPhase
        self.isCancellingInitialSetup = isCancellingInitialSetup
        self.thread = thread
        self.projects = projects
        self.sections = sections
        self.isProjectSelectionDisabled = isProjectSelectionDisabled
        self.onSelectDestination = onSelectDestination
        self.workspaceConfiguration = workspaceConfiguration
    }

    var body: some View {
        Group {
            if isCancellingInitialSetup {
                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)

                    Text("Cancelling setup")
                        .font(.title3.weight(.semibold))

                    Text("Cleaning up the partial worktree and rollback branch.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let setupPhase {
                VStack(spacing: 18) {
                    ProgressView()
                        .controlSize(.large)

                    Text(title(for: setupPhase))
                        .font(.title3.weight(.semibold))

                    Text(message(for: setupPhase))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                newThreadHero
            }
        }
    }
}

private extension EmptyThreadState {
    var projectOptions: [EmptyThreadProjectOption] {
        emptyThreadProjectOptions(projects: projects, selectedProjectID: thread?.project?.id)
    }

    var destinationName: String {
        thread?.project?.name ?? thread?.customSection?.name ?? "Tasks"
    }

    var newThreadHero: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)
            VStack(spacing: 12) {
                Text("What would you like to work on?")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
                Text("Ask your agent to explore, make changes, or help with a task.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                if thread?.isDraft == true {
                    draftDestinationControls
                } else {
                    destinationPicker
                    workspaceControl
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    var draftDestinationControls: some View {
        HStack(spacing: 6) {
            destinationPicker
                .padding(.leading, 8)
            if workspaceConfiguration != nil {
                Divider().frame(height: 18)
                workspaceControl
            }
        }
        .padding(4)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1).allowsHitTesting(false))
        .padding(.top, 4)
    }

    @ViewBuilder
    var destinationPicker: some View {
        if thread?.isDraft == true {
            Menu {
                Button("Tasks") { onSelectDestination(.tasks) }
                ForEach(sections.filter { $0.kind == .custom }.sorted { $0.name < $1.name }, id: \.id) { section in
                    Button(section.name) { onSelectDestination(.section(id: section.id)) }
                }
                if !projectOptions.isEmpty {
                    Divider()
                    ForEach(projectOptions, id: \.project.id) { option in
                        Button {
                            onSelectDestination(.project(id: option.project.id))
                        } label: {
                            Text(option.showsDisambiguatingPath
                                 ? "\(option.project.name) — \(option.displayPath)" : option.project.name)
                            if option.isSelected { Image(systemName: "checkmark") }
                        }
                    }
                }
            } label: {
                Label(destinationName, systemImage: thread?.project == nil ? "tray" : "folder")
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .menuStyle(.borderlessButton)
            .fixedSize(horizontal: false, vertical: true)
            .disabled(isProjectSelectionDisabled)
            .help("Choose where to place this thread: \(destinationName)")
            .accessibilityLabel("Thread placement")
            .accessibilityValue(destinationName)
        } else {
            Text(destinationName).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    var workspaceControl: some View {
        if let thread, thread.isDraft, let workspaceConfiguration {
            ChatWorkspaceControl(
                contextID: "\(thread.id):\(thread.project?.id ?? "tasks"):\(thread.customSection?.id ?? "")",
                configuration: workspaceConfiguration,
                isEnabled: !isProjectSelectionDisabled
            )
            .fixedSize()
        } else if thread?.isDraft != true, let source = thread?.sourceFolder {
            Text(CanonicalPath.abbreviateHomeDirectory(source.path))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(source.path)
        } else if thread?.isDraft != true {
            Text("Private workspace")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

}

private extension EmptyThreadState {
    func title(for phase: SetupPhase) -> String {
        switch phase {
        case .creatingWorktree:
            return "Creating worktree"
        case .startingAgent:
            return "Starting agent"
        }
    }

    func message(for phase: SetupPhase) -> String {
        switch phase {
        case .creatingWorktree:
            return "Preparing an isolated working directory for this thread."
        case .startingAgent:
            return "Launching the conversation runtime and preparing the first turn."
        }
    }
}
