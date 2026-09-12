import AppKit

extension ChatComposerActionRowView {
    struct TaskWorkspaceConfiguration {
        let primaryRoot: String
        let grantedRoots: [String]
        let ownershipStrategy: TaskWorkspaceOwnershipStrategy
        let canEdit: Bool
        let disabledTooltip: String?
        let onAddFolders: ([URL]) -> Void
        let onRemoveGrant: (String) -> Void
        var selectedUseWorktree: Bool?
        var onUseWorktreeChange: (Bool) -> Void = { _ in }
    }
}

extension ChatComposerActionRowView {
    func applyTaskWorkspaceConfiguration(_ configuration: Configuration) {
        guard let workspace = configuration.taskWorkspace else {
            if taskWorkspacePopover != nil {
                closeTaskWorkspaceMenu()
            }
            worktreeButton.setAccessibilityLabel("Thread location")
            worktreeButton.setAccessibilityHelp(nil)
            worktreeButton.toolTip = nil
            return
        }

        ComposerTaskWorkspacePresentation.configureButton(
            worktreeButton, workspace: workspace, isEnabled: !configuration.areControlsDisabled,
            action: { [weak self] in self?.toggleTaskWorkspaceMenu() }
        )
        taskWorkspaceMenuController?.update(configuration: workspace)
    }

    func taskWorkspaceGrantRemovalTitle(_ path: String) -> String {
        ComposerTaskWorkspacePresentation.grantRemovalAccessibilityLabel(path)
    }

    func workspaceKindName(_ strategy: TaskWorkspaceOwnershipStrategy) -> String {
        ComposerTaskWorkspacePresentation.workspaceKindName(strategy)
    }
}

extension ChatComposerActionRowView {
    enum WorkspaceControlRole: Equatable {
        case hidden
        case taskWorkspace
        case worktree
    }

    func workspaceControlRole(for configuration: Configuration) -> WorkspaceControlRole {
        if configuration.taskWorkspace != nil {
            return .taskWorkspace
        }
        if configuration.showWorktreePicker {
            return .worktree
        }
        return .hidden
    }

    func reconcileWorkspaceControl(
        previousRole: WorkspaceControlRole?,
        currentRole: WorkspaceControlRole,
        controlsAreDisabled: Bool
    ) {
        let roleChanged = previousRole.map { $0 != currentRole } ?? false
        if controlsAreDisabled || currentRole == .hidden || roleChanged {
            closeWorktreeLocationMenu()
            closeTaskWorkspaceMenu()
            return
        }

        // This button hosts two menus. Preserve pending clicks only while its
        // semantic role and compatible menu state remain unchanged.
        switch currentRole {
        case .taskWorkspace:
            if worktreePopover != nil {
                closeWorktreeLocationMenu()
            }
        case .worktree:
            if taskWorkspacePopover != nil {
                closeTaskWorkspaceMenu()
            }
        case .hidden:
            break
        }
    }
}

enum ComposerTaskWorkspacePresentation {
    @MainActor
    static func configureButton(
        _ worktreeButton: ComposerWorktreeLocationButton,
        workspace: ChatComposerActionRowView.TaskWorkspaceConfiguration,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) {
        let grantCount = workspace.grantedRoots.count
        let modeOption = workspace.selectedUseWorktree.map {
            ChatComposerWorktreeLocationPresentation.selectedOption(usesWorktree: $0)
        }
        let title = workspace.selectedUseWorktree.map { $0 ? "Worktree" : "Local" } ?? "Workspace"
        let option = ChatComposerActionRowView.WorktreeLocationOptionPresentation(
            value: "taskWorkspace",
            title: grantCount == 0 ? title : "\(title) +\(grantCount)",
            symbolName: modeOption?.symbolName ?? "folder.badge.gearshape",
            iconRotationRadians: modeOption?.iconRotationRadians ?? 0
        )
        worktreeButton.configure(
            option: option,
            height: ChatComposerActionRowView.defaultSettingsControlHeight,
            isEnabled: isEnabled,
            actionHandler: action
        )
        worktreeButton.setAccessibilityLabel("Thread workspace")
        let workspaceKind = modeOption?.title ?? workspaceKindName(workspace.ownershipStrategy)
        worktreeButton.setAccessibilityValue(
            grantCount == 0
                ? "\(workspaceKind), no additional folders"
                : "\(workspaceKind), \(grantCount) additional folder\(grantCount == 1 ? "" : "s")"
        )
        let disabledReason = workspace.canEdit ? nil : workspace.disabledTooltip
        worktreeButton.toolTip = disabledReason
        worktreeButton.setAccessibilityHelp(disabledReason)
    }

    static func grantRemovalAccessibilityLabel(_ path: String) -> String {
        "Remove Access to \(grantDisplayPath(path))"
    }

    static func grantDisplayPath(_ path: String) -> String {
        CanonicalPath.abbreviateHomeDirectory(path)
    }

    static func workspaceKindName(_ strategy: TaskWorkspaceOwnershipStrategy) -> String {
        switch strategy {
        case .privateOwned:
            return "Private workspace"
        case .projectLocal:
            return "Project workspace"
        case .projectWorktreeOwned:
            return "Thread worktree"
        }
    }
}
