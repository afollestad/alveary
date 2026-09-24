import AppKit
import SwiftUI

/// A settings row's agent choice: the reasoning button styled as a settings field, opening the reasoning popover below
/// itself. The host owns what `presentation` lists and stores whatever pins `apply` receives.
struct SettingsAgentSelector: NSViewRepresentable {
    let accessibilityLabel: String
    let presentation: AgentReasoningPresentation
    /// Returns `false` to reject a pick, which closes the popover without moving its selection.
    let apply: (AgentReasoningPins) -> Bool

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> ComposerReasoningButton {
        context.coordinator.button
    }

    func updateNSView(_ nsView: ComposerReasoningButton, context: Context) {
        context.coordinator.update(accessibilityLabel: accessibilityLabel, presentation: presentation, apply: apply)
    }

    static func dismantleNSView(_ nsView: ComposerReasoningButton, coordinator: Coordinator) {
        coordinator.close()
    }

    /// Mirrors `SettingsMenuPicker`: its content width when unconstrained, otherwise the proposed width.
    func sizeThatFits(_ proposal: ProposedViewSize, nsView: ComposerReasoningButton, context: Context) -> CGSize? {
        let width = proposal.width.flatMap { $0.isFinite ? max($0, SettingsScreenLayout.settingsPickerWidth) : nil }
        return CGSize(
            width: width ?? nsView.intrinsicContentSize.width,
            height: SettingsScreenLayout.settingsControlSurfaceHeight
        )
    }
}

extension SettingsAgentSelector {
    @MainActor
    final class Coordinator {
        let button = ComposerReasoningButton(presentation: .settingsField)
        private(set) lazy var presenter = ComposerReasoningMenuPresenter(
            direction: .below,
            onDisplaySelectionChanged: { [weak self] selection in
                self?.displaySelection = selection
                self?.configureButton()
            }
        )
        private var presentation: AgentReasoningPresentation?
        private var apply: ((AgentReasoningPins) -> Bool)?
        /// The popover's in-flight effort preview, painted until the drag commits or the popover closes.
        private var displaySelection: ReasoningSelection?
        private var hasPendingMenuUpdate = false

        func update(
            accessibilityLabel: String,
            presentation: AgentReasoningPresentation,
            apply: @escaping (AgentReasoningPins) -> Bool
        ) {
            self.apply = apply
            button.setAccessibilityLabel(accessibilityLabel)
            guard presentation != self.presentation else {
                return
            }
            self.presentation = presentation
            configureButton()
            scheduleMenuUpdate()
        }

        func close() {
            presenter.close()
        }

        /// The window's content view, not the button: a popover follows its positioning view, and the button resizes as
        /// each effort preview relabels it, which would slide the slider out from under the drag.
        var popoverAnchor: (view: NSView, rect: NSRect)? {
            guard let contentView = button.window?.contentView else {
                return nil
            }
            return (contentView, button.convert(button.bounds, to: contentView))
        }

        private var configuration: ReasoningConfiguration? {
            presentation.map { presentation in
                ReasoningConfiguration(presentation: presentation, apply: { [weak self] pins in
                    self?.apply?(pins) ?? false
                })
            }
        }

        private func configureButton() {
            guard let presentation else {
                return
            }
            button.configure(
                selection: displaySelection ?? presentation.selection,
                title: presentation.buttonTitle,
                height: SettingsScreenLayout.settingsControlSurfaceHeight,
                isEnabled: presentation.availability == .ready,
                showsProgress: presentation.availability == .checking,
                actionHandler: { [weak self] in
                    self?.togglePopover()
                }
            )
        }

        private func togglePopover() {
            guard let configuration, let anchor = popoverAnchor else {
                return
            }
            presenter.toggle(configuration: configuration, anchorView: anchor.view, anchorRect: anchor.rect)
        }

        /// SwiftUI calls `updateNSView` mid-transaction, and an open popover re-shows itself when an update resizes it;
        /// deferring to the next main-queue turn keeps that window work out of the view update and coalesces bursts.
        private func scheduleMenuUpdate() {
            guard presenter.controller != nil, !hasPendingMenuUpdate else {
                return
            }
            hasPendingMenuUpdate = true
            DispatchQueue.main.async { [weak self] in
                guard let self else {
                    return
                }
                hasPendingMenuUpdate = false
                if let configuration {
                    presenter.update(configuration: configuration)
                }
            }
        }
    }
}
