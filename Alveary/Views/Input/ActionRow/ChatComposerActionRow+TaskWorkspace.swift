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

        let grantCount = workspace.grantedRoots.count
        let option = WorktreeLocationOptionPresentation(
            value: "taskWorkspace",
            title: grantCount == 0 ? "Workspace" : "Workspace +\(grantCount)",
            symbolName: "folder.badge.gearshape",
            iconRotationRadians: 0
        )
        worktreeButton.configure(
            option: option,
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            actionHandler: { [weak self] in
                self?.toggleTaskWorkspaceMenu()
            }
        )
        worktreeButton.setAccessibilityLabel("Task workspace")
        let workspaceKind = workspaceKindName(workspace.ownershipStrategy)
        worktreeButton.setAccessibilityValue(
            grantCount == 0
                ? "\(workspaceKind), no additional folders"
                : "\(workspaceKind), \(grantCount) additional folder\(grantCount == 1 ? "" : "s")"
        )
        let disabledReason = workspace.canEdit ? nil : workspace.disabledTooltip
        worktreeButton.toolTip = disabledReason
        worktreeButton.setAccessibilityHelp(disabledReason)
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
    static func grantRemovalAccessibilityLabel(_ path: String) -> String {
        "Remove Access to \(grantDisplayPath(path))"
    }

    static func grantDisplayPath(_ path: String) -> String {
        CanonicalPath.abbreviateHomeDirectory(CanonicalPath.normalize(path))
    }

    static func workspaceKindName(_ strategy: TaskWorkspaceOwnershipStrategy) -> String {
        switch strategy {
        case .privateOwned:
            return "Private workspace"
        case .projectLocal:
            return "Project workspace"
        case .projectWorktreeOwned:
            return "Task worktree"
        }
    }
}
