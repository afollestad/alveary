import AppKit
import SwiftUI

/// Hosts the composer's existing workspace button and menu beside draft placement.
struct ChatWorkspaceControl: NSViewRepresentable {
    let contextID: String
    let configuration: ChatComposerActionRowView.TaskWorkspaceConfiguration
    let isEnabled: Bool

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> ComposerWorktreeLocationButton {
        let button = ComposerWorktreeLocationButton()
        context.coordinator.button = button
        return button
    }

    func updateNSView(_ button: ComposerWorktreeLocationButton, context: Context) {
        context.coordinator.update(self)
        ComposerTaskWorkspacePresentation.configureButton(
            button, workspace: configuration, isEnabled: isEnabled,
            action: { [weak coordinator = context.coordinator] in coordinator?.toggleMenu() }
        )
    }

    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ComposerWorktreeLocationButton, context: Context) -> CGSize? {
        nsView.intrinsicContentSize
    }

    static func dismantleNSView(_ button: ComposerWorktreeLocationButton, coordinator: Coordinator) {
        coordinator.invalidate()
        button.actionHandler = nil
    }

    @MainActor
    final class Coordinator: NSObject, NSPopoverDelegate {
        weak var button: ComposerWorktreeLocationButton?
        private var control: ChatWorkspaceControl?
        var popover: NSPopover?
        private var folderPicker: NSOpenPanel?

        func update(_ next: ChatWorkspaceControl) {
            if let control, !hasSameWorkspace(control, next) || !next.isEnabled {
                closeMenu()
                folderPicker?.cancel(nil)
                folderPicker = nil
            }
            control = next
        }

        func toggleMenu() {
            guard let control, control.isEnabled, let button, button.window != nil else { return }
            guard popover == nil else { closeMenu(); return }
            let controller = makeMenuController(for: control)
            let popover = NSPopover()
            popover.behavior = .transient
            popover.animates = false
            popover.delegate = self
            popover.contentViewController = controller
            self.popover = popover
            popover.show(
                relativeTo: button.bounds, of: button,
                preferredEdge: ComposerReasoningMenuPresenter.upwardEdge(for: button)
            )
        }

        func makeMenuController(for control: ChatWorkspaceControl) -> ComposerTaskWorkspaceMenuViewController {
            var configuration = control.configuration
            configuration.onUseWorktreeChange = { [weak self] value in
                self?.performAction(for: control) { $0.onUseWorktreeChange(value) }
            }
            return ComposerTaskWorkspaceMenuViewController(
                configuration: configuration,
                onAddFolders: { [weak self] in
                    guard let self else { return }
                    performAction(for: control) { _ in
                        closeMenu()
                        chooseFolders()
                    }
                },
                onRemoveGrant: { [weak self] path in
                    guard let self else { return }
                    performAction(for: control) {
                        closeMenu()
                        $0.onRemoveGrant(path)
                    }
                },
                onRequestClose: { [weak self] in
                    guard let self, let current = self.control, hasSameWorkspace(control, current) else { return }
                    closeMenu()
                }
            )
        }

        private func performAction(
            for captured: ChatWorkspaceControl,
            action: (ChatComposerActionRowView.TaskWorkspaceConfiguration) -> Void
        ) {
            guard let current = control, current.isEnabled, current.configuration.canEdit,
                  hasSameWorkspace(captured, current) else { return }
            action(current.configuration)
        }

        func closeMenu() {
            popover?.delegate = nil
            popover?.performClose(nil)
            popover = nil
            button?.releaseMenuFocusIfNeeded()
        }

        func popoverDidClose(_ notification: Notification) {
            guard notification.object as? NSPopover === popover else { return }
            closeMenu()
        }

        func invalidate() {
            control = nil
            closeMenu()
            folderPicker?.cancel(nil)
            folderPicker = nil
        }

        private func chooseFolders() {
            guard let control, control.isEnabled, control.configuration.canEdit,
                  let window = button?.window else { return }
            let picker = makeTaskWorkspaceFolderPicker()
            folderPicker = picker
            picker.beginSheetModal(for: window) { [weak self] response in
                guard let self, folderPicker === picker else { return }
                folderPicker = nil
                guard response == .OK, let current = self.control, current.isEnabled, current.configuration.canEdit,
                      hasSameWorkspace(control, current) else { return }
                current.configuration.onAddFolders(picker.urls)
            }
        }

        private func hasSameWorkspace(_ lhs: ChatWorkspaceControl, _ rhs: ChatWorkspaceControl) -> Bool {
            lhs.contextID == rhs.contextID
                && lhs.configuration.primaryRoot == rhs.configuration.primaryRoot
                && lhs.configuration.grantedRoots == rhs.configuration.grantedRoots
                && lhs.configuration.ownershipStrategy == rhs.configuration.ownershipStrategy
                && lhs.configuration.selectedUseWorktree == rhs.configuration.selectedUseWorktree
                && lhs.configuration.canEdit == rhs.configuration.canEdit
                && lhs.configuration.disabledTooltip == rhs.configuration.disabledTooltip
        }
    }
}
