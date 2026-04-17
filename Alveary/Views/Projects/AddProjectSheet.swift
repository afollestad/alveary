import AppKit
import SwiftUI

struct AddProjectSheet: View {
    let viewModel: SidebarViewModel
    let settingsService: SettingsService
    let onChooseFromDisk: () -> Void
    let onProjectCreated: (Project) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var step: Step
    @State private var draft: CloneDraft
    @State private var cloneTask: Task<Void, Never>?

    init(
        viewModel: SidebarViewModel,
        settingsService: SettingsService,
        onChooseFromDisk: @escaping () -> Void,
        onProjectCreated: @escaping (Project) -> Void,
        initialStep: Step = .chooser,
        initialDraft: CloneDraft? = nil
    ) {
        self.viewModel = viewModel
        self.settingsService = settingsService
        self.onChooseFromDisk = onChooseFromDisk
        self.onProjectCreated = onProjectCreated
        _step = State(initialValue: initialStep)

        var resolvedDraft = initialDraft ?? CloneDraft()
        if initialDraft == nil,
           let stored = settingsService.current.lastAddProjectParentFolder?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !stored.isEmpty {
            resolvedDraft.parentPath = stored
        }
        _draft = State(initialValue: resolvedDraft)
    }

    enum Step: Equatable {
        case chooser
        case cloneForm
        case cloneRunning
        case cloneFailed(String)
    }

    struct CloneDraft: Equatable {
        var url: String = ""
        var parentPath: String = "~/Documents"
        var folderName: String = ""
        var branch: String = ""
        // Latches on the first manual edit and never resets: once the user owns
        // the folder name we stop overwriting it from the URL, even if they
        // clear the field or rewrite the URL later.
        var folderNameIsDirty: Bool = false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text(title)
                    .font(.title2.weight(.semibold))

                Spacer()

                ModalCloseButton("Close add project") {
                    cancelInFlightClone()
                    dismiss()
                }
            }

            stepContent
        }
        .padding(24)
        .frame(minWidth: 520, minHeight: 340)
        .onDisappear {
            cancelInFlightClone()
        }
    }
}

private extension AddProjectSheet {
    var title: String {
        switch step {
        case .chooser:
            return "Add Project"
        case .cloneForm, .cloneRunning, .cloneFailed:
            return "Clone from Git"
        }
    }

    @ViewBuilder
    var stepContent: some View {
        switch step {
        case .chooser:
            chooserStep
        case .cloneForm:
            cloneFormStep
        case .cloneRunning:
            cloneRunningStep
        case .cloneFailed(let message):
            cloneFailedStep(message: message)
        }
    }

    var chooserStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                onChooseFromDisk()
            } label: {
                chooserLabel(
                    icon: "folder",
                    title: "Add From Disk",
                    subtitle: "Pick a folder that already exists on your Mac."
                )
            }
            .buttonStyle(AddProjectOptionCardButtonStyle())

            Button {
                step = .cloneForm
            } label: {
                chooserLabel(
                    icon: "arrow.down.doc",
                    title: "Clone from Git",
                    subtitle: "Clone a remote repository into a new folder."
                )
            }
            .buttonStyle(AddProjectOptionCardButtonStyle())

            Spacer(minLength: 0)
        }
    }

    func chooserLabel(icon: String, title: String, subtitle: String) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    var cloneFormStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Repository URL")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AppTextField(
                "https://github.com/owner/repo.git",
                text: Binding(
                    get: { draft.url },
                    set: { newValue in
                        draft.url = newValue
                        if !draft.folderNameIsDirty {
                            draft.folderName = Self.defaultFolderName(for: newValue)
                        }
                    }
                )
            )

            Text("Parent Folder")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            parentFolderRow

            Text("Folder Name")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AppTextField(
                "repo",
                text: Binding(
                    get: { draft.folderName },
                    set: { newValue in
                        draft.folderName = newValue
                        draft.folderNameIsDirty = true
                    }
                )
            )

            Text("Branch (optional)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            AppTextField("main", text: $draft.branch)

            HStack {
                Button("Back") {
                    step = .chooser
                }
                .secondaryActionButtonStyle()
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Clone") {
                    startClone()
                }
                .primaryActionButtonStyle()
                .disabled(!canStartClone)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    var parentFolderRow: some View {
        HStack(spacing: 10) {
            Text(displayParentPath)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .truncationMode(.middle)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.secondary.opacity(0.08))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                )

            Button {
                chooseParentFolder()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "folder")
                    Text("Choose…")
                }
            }
            .secondaryActionButtonStyle()
        }
    }

    var cloneRunningStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 12) {
                ProgressView()
                    .controlSize(.small)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Cloning \(draft.url)")
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("Into \(displayDestinationPath)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Cancel") {
                    cancelInFlightClone()
                    step = .cloneForm
                }
                .secondaryActionButtonStyle()
                .keyboardShortcut(.cancelAction)
            }
        }
    }

    func cloneFailedStep(message: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            InlineBanner(message: message, severity: .error, autoDismissAfter: nil)

            Spacer(minLength: 0)

            HStack {
                Button("Back") {
                    step = .chooser
                }
                .secondaryActionButtonStyle()
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Retry") {
                    startClone()
                }
                .primaryActionButtonStyle()
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    var canStartClone: Bool {
        let url = draft.url.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = draft.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = draft.parentPath.trimmingCharacters(in: .whitespacesAndNewlines)
        return !url.isEmpty && !folder.isEmpty && !parent.isEmpty
    }

    var displayParentPath: String {
        let expanded = (draft.parentPath as NSString).expandingTildeInPath
        return CanonicalPath.abbreviateHomeDirectory(expanded)
    }

    var displayDestinationPath: String {
        CanonicalPath.abbreviateHomeDirectory(resolvedDestinationPath())
    }

    func resolvedDestinationPath() -> String {
        let expandedParent = (draft.parentPath as NSString).expandingTildeInPath
        let folder = draft.folderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (expandedParent as NSString).appendingPathComponent(folder)
    }

    func chooseParentFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Parent Folder"
        panel.prompt = "Choose"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true

        let expanded = (draft.parentPath as NSString).expandingTildeInPath
        if FileManager.default.fileExists(atPath: expanded) {
            panel.directoryURL = URL(fileURLWithPath: expanded)
        }

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }
        let abbreviated = (url.path as NSString).abbreviatingWithTildeInPath
        draft.parentPath = abbreviated
        settingsService.update { $0.lastAddProjectParentFolder = abbreviated }
    }

    func startClone() {
        cancelInFlightClone()
        step = .cloneRunning

        let draftSnapshot = draft
        let destination = resolvedDestinationPath()
        let branch = draftSnapshot.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        let url = draftSnapshot.url.trimmingCharacters(in: .whitespacesAndNewlines)

        cloneTask = Task { @MainActor in
            do {
                let project = try await viewModel.cloneRepository(
                    url: url,
                    into: destination,
                    branch: branch.isEmpty ? nil : branch
                )
                // Cancellation after persistence has already lost the race — committing
                // to the success path avoids orphaning a cloned project in SwiftData.
                // The parent drives dismissal via its `isPresented` binding; calling
                // `dismiss()` here too would be redundant.
                onProjectCreated(project)
            } catch is CancellationError {
                // User-initiated cancel is surfaced by whichever code path cancelled the task.
                return
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                step = .cloneFailed(error.localizedDescription)
            }
        }
    }

    func cancelInFlightClone() {
        cloneTask?.cancel()
        cloneTask = nil
    }

    static func defaultFolderName(for url: String) -> String {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return ""
        }

        let lastComponent = trimmed
            .split(whereSeparator: { $0 == "/" || $0 == ":" })
            .last
            .map(String.init) ?? ""
        return lastComponent.hasSuffix(".git")
            ? String(lastComponent.dropLast(4))
            : lastComponent
    }
}

private struct AddProjectOptionCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        AddProjectOptionCardBody(configuration: configuration)
    }
}

private struct AddProjectOptionCardBody: View {
    let configuration: ButtonStyle.Configuration

    @State private var isHovering = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        configuration.label
            .padding(.horizontal, 16)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.25), lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { hovering in
                guard isEnabled else {
                    return
                }
                isHovering = hovering
            }
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }

    private var backgroundFill: Color {
        if configuration.isPressed {
            return Color.primary.opacity(0.14)
        }
        if isHovering {
            return Color.primary.opacity(0.09)
        }
        return Color.primary.opacity(0.05)
    }
}
