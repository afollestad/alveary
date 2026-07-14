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

struct EmptyThreadProjectIdentityPresentation: Equatable {
    let helpText: String
    let accessibilityValue: String
}

@MainActor
func emptyThreadProjectOptions(
    projects: [Project],
    selectedProjectPath: String?
) -> [EmptyThreadProjectOption] {
    let sortedProjects = projects.sorted { lhs, rhs in
        let comparison = lhs.name.localizedCaseInsensitiveCompare(rhs.name)
        if comparison != .orderedSame {
            return comparison == .orderedAscending
        }
        return lhs.path < rhs.path
    }

    return sortedProjects.map { project in
        EmptyThreadProjectOption(
            project: project,
            showsDisambiguatingPath: sortedProjects.contains { candidate in
                candidate.persistentModelID != project.persistentModelID &&
                    candidate.name.localizedCaseInsensitiveCompare(project.name) == .orderedSame
            },
            isSelected: project.path == selectedProjectPath
        )
    }
}

func emptyThreadProjectIdentityPresentation(
    name: String,
    path: String?
) -> EmptyThreadProjectIdentityPresentation {
    guard let path else {
        return EmptyThreadProjectIdentityPresentation(helpText: name, accessibilityValue: name)
    }
    return EmptyThreadProjectIdentityPresentation(
        helpText: "\(name)\n\(path)",
        accessibilityValue: "\(name), \(path)"
    )
}

struct EmptyThreadState: View {
    let setupPhase: SetupPhase?
    let isCancellingInitialSetup: Bool
    let thread: AgentThread?
    let projects: [Project]
    let onSelectProject: (String) -> Void

    init(
        setupPhase: SetupPhase?,
        isCancellingInitialSetup: Bool,
        thread: AgentThread? = nil,
        projects: [Project] = [],
        onSelectProject: @escaping (String) -> Void = { _ in }
    ) {
        self.setupPhase = setupPhase
        self.isCancellingInitialSetup = isCancellingInitialSetup
        self.thread = thread
        self.projects = projects
        self.onSelectProject = onSelectProject
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
        emptyThreadProjectOptions(projects: projects, selectedProjectPath: projectPath)
    }

    var projectName: String {
        thread?.project?.name ?? "this project"
    }

    var projectPath: String? {
        thread?.project?.path
    }

    var projectIdentityPresentation: EmptyThreadProjectIdentityPresentation {
        emptyThreadProjectIdentityPresentation(name: projectName, path: projectPath)
    }

    var newThreadHero: some View {
        Group {
            if thread?.effectiveMode == .task {
                taskThreadHero
            } else {
                projectThreadHero
            }
        }
    }

    var projectThreadHero: some View {
        VStack(spacing: 24) {
            Image(systemName: "sparkles")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    oneLineProjectQuestion
                        .fixedSize(horizontal: true, vertical: false)

                    twoLineProjectQuestion
                        .fixedSize(horizontal: true, vertical: false)

                    truncatedTwoLineProjectQuestion
                }
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)

                Text(
                    "Ask your agent to explore the project, make changes, or explain what it finds. " +
                        "Your first message will start the session."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    var taskThreadHero: some View {
        VStack(spacing: 24) {
            Image(systemName: "checklist")
                .font(.system(size: 42, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(spacing: 12) {
                Text("What should this task do?")
                    .font(.title.weight(.semibold))

                Text(
                    "Your first message starts the task in \(taskWorkspaceIntroLocation). " +
                        "Use Workspace below to grant access to additional folders."
                )
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)

                if let workspace = thread?.taskWorkspaceDescriptor {
                    Text(taskWorkspaceSummary(workspace))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .help(taskWorkspaceHelp(workspace))
                        .accessibilityLabel("Task workspace")
                        .accessibilityValue(taskWorkspaceHelp(workspace))
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    func taskWorkspaceSummary(_ workspace: TaskWorkspaceDescriptor) -> String {
        let rootName = URL(fileURLWithPath: workspace.primaryRoot, isDirectory: true).lastPathComponent
        let workspaceKind: String
        switch workspace.ownershipStrategy {
        case .privateOwned:
            workspaceKind = "Private workspace"
        case .projectLocal:
            workspaceKind = "Project workspace"
        case .projectWorktreeOwned:
            workspaceKind = "Task worktree"
        }
        let count = workspace.grantedRoots.count
        guard count > 0 else {
            return "\(workspaceKind): \(rootName)"
        }
        return "\(workspaceKind): \(rootName) · \(count) additional folder\(count == 1 ? "" : "s")"
    }

    var taskWorkspaceIntroLocation: String {
        switch thread?.taskWorkspaceDescriptor?.ownershipStrategy {
        case .projectLocal:
            return "the project workspace"
        case .projectWorktreeOwned:
            return "a dedicated task worktree"
        case .privateOwned, nil:
            return "a private workspace"
        }
    }

    func taskWorkspaceHelp(_ workspace: TaskWorkspaceDescriptor) -> String {
        ([workspace.primaryRoot] + workspace.grantedRoots).joined(separator: "\n")
    }

    @ViewBuilder
    var projectHeading: some View {
        if thread?.isDraft == true, projectPath != nil {
            Menu {
                ForEach(projectOptions, id: \.project.persistentModelID) { option in
                    Button {
                        onSelectProject(option.project.path)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(option.project.name)
                                if option.showsDisambiguatingPath {
                                    Text(option.displayPath)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if option.isSelected {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                }
            } label: {
                projectNameLabel(isUnderlined: true)
            }
            .menuIndicator(.hidden)
            .buttonStyle(.plain)
            .help(projectIdentityPresentation.helpText)
            .accessibilityLabel("Project")
            .accessibilityValue(projectIdentityPresentation.accessibilityValue)
        } else {
            projectNameLabel(isUnderlined: false)
                .help(projectIdentityPresentation.helpText)
                .accessibilityLabel("Project")
                .accessibilityValue(projectIdentityPresentation.accessibilityValue)
        }
    }

    var oneLineProjectQuestion: some View {
        HStack(spacing: 0) {
            Text("What should we build in")
            projectHeading
                .padding(.leading, 8)
            Text("?")
        }
    }

    var twoLineProjectQuestion: some View {
        VStack(spacing: 2) {
            Text("What should we build in")
            HStack(spacing: 0) {
                projectHeading
                Text("?")
            }
        }
    }

    var truncatedTwoLineProjectQuestion: some View {
        VStack(spacing: 2) {
            Text("What should we build in")
            HStack(spacing: 0) {
                projectHeading
                    .frame(maxWidth: .infinity)
                Text("?")
                    .fixedSize(horizontal: true, vertical: false)
            }
            // The middle pane can be 420 points wide. Its 40-point horizontal
            // padding leaves a 340-point proposal, so this cap must remain flexible
            // rather than forcing the full 360-point ideal width.
            .frame(maxWidth: 360)
        }
    }

    func projectNameLabel(isUnderlined: Bool) -> some View {
        Text(projectName)
            .lineLimit(1)
            .truncationMode(.middle)
            .overlay(alignment: .bottom) {
                if isUnderlined {
                    Rectangle()
                        .frame(height: 1)
                        .offset(y: 2)
                }
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
