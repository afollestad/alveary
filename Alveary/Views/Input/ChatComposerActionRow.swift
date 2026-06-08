import AppKit
import SwiftUI

/// SwiftUI bridge for the native composer action row.
///
/// AppKit owns migrated composer controls because Alveary's variable-height
/// transcript/composer stack needs deterministic measurement and responder
/// behavior. SwiftUI's lazy/recycling and measurement behavior caused scroll
/// position and performance issues in this UX, so new composer internals should
/// prefer native views.
struct ChatComposerActionRow: NSViewRepresentable {
    let reasoningConfiguration: ChatComposerActionRowView.ReasoningConfiguration
    let supportedPermissionModes: [PermissionModeOption]
    @Binding var selectedPermissionMode: String
    let showWorktreePicker: Bool
    @Binding var selectedUseWorktree: Bool
    @Binding var isPlanModeEnabled: Bool
    let isPlanModeToggleEnabled: Bool
    let planModeDisabledTooltip: String?
    let sessionLocationLabel: String?
    let usageSummary: ConversationUsageSummary?
    let areControlsDisabled: Bool
    let mode: ComposerMode
    let primaryActionTitle: String
    let primaryActionSystemImage: String
    let isPrimaryActionDisabled: Bool
    let isStopConfirmationArmed: Bool
    let composerActionRowHeight: CGFloat
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onAddPhotosAndFiles: () -> Void

    func makeNSView(context: Context) -> ChatComposerActionRowView {
        let view = ChatComposerActionRowView()
        view.configure(configuration)
        return view
    }

    func updateNSView(_ view: ChatComposerActionRowView, context: Context) {
        view.configure(configuration)
    }

    private var configuration: ChatComposerActionRowView.Configuration {
        ChatComposerActionRowView.Configuration(
            reasoning: reasoningConfiguration,
            supportedPermissionModes: ChatComposerPermissionPresentation.options(
                providerID: reasoningConfiguration.selection.providerID,
                permissionModes: supportedPermissionModes
            ),
            selectedPermissionMode: selectedPermissionMode,
            showWorktreePicker: showWorktreePicker,
            selectedUseWorktree: selectedUseWorktree,
            isPlanModeEnabled: isPlanModeEnabled,
            isPlanModeToggleEnabled: isPlanModeToggleEnabled,
            planModeDisabledTooltip: planModeDisabledTooltip,
            sessionLocationLabel: sessionLocationLabel,
            usageSummary: usageSummary,
            areControlsDisabled: areControlsDisabled,
            mode: mode,
            primaryActionTitle: primaryActionTitle,
            primaryActionSystemImage: primaryActionSystemImage,
            isPrimaryActionDisabled: isPrimaryActionDisabled,
            isStopConfirmationArmed: isStopConfirmationArmed,
            composerActionRowHeight: composerActionRowHeight,
            onPermissionModeChange: { selectedPermissionMode = $0 },
            onUseWorktreeChange: { selectedUseWorktree = $0 },
            onPlanModeChange: { isPlanModeEnabled = $0 },
            onSubmit: onSubmit,
            onStop: onStop,
            onAddPhotosAndFiles: onAddPhotosAndFiles
        )
    }
}

/// Native bottom composer row for reasoning/permission/worktree selectors,
/// context usage, and send/stop/progress action slots.
@MainActor
final class ChatComposerActionRowView: NSView {
    nonisolated static let defaultHeight: CGFloat = 30
    nonisolated static let defaultSettingsControlHeight: CGFloat = 24

    struct MenuOption: Equatable {
        let value: String
        let title: String
    }

    struct ReasoningSelection: Equatable {
        let providerID: String
        let providerTitle: String
        let modelID: String
        let modelTitle: String
        let effortValue: String
        let effortTitle: String
        let effortOptions: [MenuOption]

        var accessibilityValue: String {
            effortOptions.isEmpty ? modelTitle : "\(modelTitle), \(effortTitle)"
        }
    }

    struct ReasoningModelOption: Equatable {
        let providerID: String
        let value: String
        let title: String

        var identity: String {
            // Model IDs such as `default` can appear under multiple providers.
            "\(providerID):\(value)"
        }
    }

    struct ReasoningModelGroup: Equatable {
        let providerID: String
        let providerTitle: String?
        let options: [ReasoningModelOption]
    }

    struct ReasoningModelSelectionRequest: Equatable {
        let providerID: String
        let modelID: String
    }

    enum ReasoningModelSelectionOutcome {
        case rejected
        case unchanged(ReasoningSelection)
        case applied(selection: ReasoningSelection)
    }

    struct ReasoningConfiguration {
        var selection: ReasoningSelection
        var modelGroups: [ReasoningModelGroup]
        var hasStartedThread: Bool
        var onEffortChange: (String) -> Bool
        var onModelChange: (ReasoningModelSelectionRequest) -> ReasoningModelSelectionOutcome
    }

    struct Configuration {
        let reasoning: ReasoningConfiguration
        let supportedPermissionModes: [PermissionOptionPresentation]
        let selectedPermissionMode: String
        let showWorktreePicker: Bool
        let selectedUseWorktree: Bool
        var isPlanModeEnabled = false
        var isPlanModeToggleEnabled = false
        var planModeDisabledTooltip: String?
        let sessionLocationLabel: String?
        let usageSummary: ConversationUsageSummary?
        let areControlsDisabled: Bool
        let mode: ComposerMode
        let primaryActionTitle: String
        let primaryActionSystemImage: String
        let isPrimaryActionDisabled: Bool
        let isStopConfirmationArmed: Bool
        let composerActionRowHeight: CGFloat
        let onPermissionModeChange: (String) -> Void
        let onUseWorktreeChange: (Bool) -> Void
        var onPlanModeChange: (Bool) -> Void = { _ in }
        let onSubmit: () -> Void
        let onStop: () -> Void
        var onAddPhotosAndFiles: () -> Void = {}
    }

    let plusButton = ComposerPlusButton()
    let reasoningButton = ComposerReasoningButton()
    let permissionButton = ComposerPermissionButton()
    let worktreeButton = ComposerWorktreeLocationButton()
    let sessionLocationField = NSTextField(labelWithString: "")
    // Internal so `ChatComposerActionRow+Layout.swift` can keep the overflow
    // frame logic out of this already-large view type without widening behavior.
    let spacer = NSView()
    let contextIndicatorView = AppKitContextWindowIndicatorView()
    private let primaryButton = ComposerActionButton(style: .primary)
    private let stopButton = ComposerActionButton(style: .destructive)
    let disabledSendSlot = ComposerActionButton(style: .primary)
    let disabledProgressContainer = NSView()
    private let progressIndicator = NSProgressIndicator()
    private let disabledSlotProgressIndicator = NSProgressIndicator()
    private let progressLabel = NSTextField(labelWithString: "")
    private let progressStack = NSStackView()
    let stack = NSView()
    var rowSubviews: [NSView] = []

    var configuration: Configuration?
    var plusPopover: NSPopover?
    var reasoningPopover: NSPopover?
    var reasoningMenuController: ComposerReasoningMenuViewController?
    var permissionPopover: NSPopover?
    var permissionMenuController: ComposerPermissionMenuViewController?
    var worktreePopover: NSPopover?
    var worktreeMenuController: ComposerWorktreeMenuViewController?
    private var progressStackHeightConstraint: NSLayoutConstraint?
    let rowSpacing: CGFloat = 10
    let plusControlVisibleSpacing: CGFloat = 20
    let leadingControlVisibleSpacing: CGFloat = 16
    let contextReasoningVisibleSpacing: CGFloat = 12
    let reasoningActionVisibleSpacing: CGFloat = 16
    let minimumSettingsControlWidth: CGFloat = 44

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupViews()
    }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: configuration?.composerActionRowHeight ?? Self.defaultHeight)
    }

    override func layout() {
        super.layout()
        layoutArrangedSubviews()
    }

    override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            closePlusMenu()
            closeReasoningMenu()
            closePermissionMenu()
            closeWorktreeLocationMenu()
        }
    }

    func configure(_ configuration: Configuration) {
        self.configuration = configuration
        applyConfiguration()
    }

    private func setupViews() {
        translatesAutoresizingMaskIntoConstraints = false
        setupStack()
        setupMenuAccessibility()
        setupAccessoryViews()
        setupActions()
        setupProgressViews()
        setupSpacer()
    }

    private func setupStack() {
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    private func setupMenuAccessibility() {
        plusButton.setAccessibilityLabel("Open composer actions")
        reasoningButton.setAccessibilityLabel("Reasoning")
        permissionButton.setAccessibilityLabel("Permissions")
        worktreeButton.setAccessibilityLabel("Thread location")
    }

    private func setupAccessoryViews() {
        sessionLocationField.font = .preferredFont(forTextStyle: .callout)
        sessionLocationField.textColor = .secondaryLabelColor
        sessionLocationField.lineBreakMode = .byTruncatingTail
        sessionLocationField.maximumNumberOfLines = 1

        contextIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        contextIndicatorView.setContentHuggingPriority(.required, for: .horizontal)
    }

    private func setupActions() {
        plusButton.actionHandler = { [weak self] in
            self?.togglePlusMenu()
        }
        reasoningButton.actionHandler = { [weak self] in
            self?.toggleReasoningMenu()
        }
        permissionButton.actionHandler = { [weak self] in
            self?.togglePermissionMenu()
        }
        worktreeButton.actionHandler = { [weak self] in
            self?.toggleWorktreeLocationMenu()
        }
        primaryButton.actionHandler = { [weak self] in
            self?.configuration?.onSubmit()
        }
        stopButton.actionHandler = { [weak self] in
            self?.configuration?.onStop()
        }

        disabledSendSlot.setAccessibilityElement(false)
    }

    private func setupProgressViews() {
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .small
        progressIndicator.isDisplayedWhenStopped = true
        progressIndicator.startAnimation(nil)
        disabledSlotProgressIndicator.style = .spinning
        disabledSlotProgressIndicator.controlSize = .small
        disabledSlotProgressIndicator.isDisplayedWhenStopped = true
        disabledSlotProgressIndicator.startAnimation(nil)
        progressLabel.font = .preferredFont(forTextStyle: .caption1)
        progressLabel.textColor = .secondaryLabelColor
        progressLabel.lineBreakMode = .byTruncatingTail

        progressStack.orientation = .horizontal
        progressStack.alignment = .centerY
        progressStack.spacing = 8
        progressStack.addArrangedSubview(progressIndicator)
        progressStack.addArrangedSubview(progressLabel)
        progressStackHeightConstraint = progressStack.heightAnchor.constraint(equalToConstant: Self.defaultHeight)
        progressStackHeightConstraint?.isActive = true

        disabledSendSlot.translatesAutoresizingMaskIntoConstraints = false
        disabledSlotProgressIndicator.translatesAutoresizingMaskIntoConstraints = false
        disabledProgressContainer.setAccessibilityElement(true)
        disabledProgressContainer.setAccessibilityRole(.group)
        disabledProgressContainer.setAccessibilityLabel("Sending message")
        disabledProgressContainer.addSubview(disabledSendSlot)
        disabledProgressContainer.addSubview(disabledSlotProgressIndicator)
        NSLayoutConstraint.activate([
            disabledSendSlot.leadingAnchor.constraint(equalTo: disabledProgressContainer.leadingAnchor),
            disabledSendSlot.trailingAnchor.constraint(equalTo: disabledProgressContainer.trailingAnchor),
            disabledSendSlot.topAnchor.constraint(equalTo: disabledProgressContainer.topAnchor),
            disabledSendSlot.bottomAnchor.constraint(equalTo: disabledProgressContainer.bottomAnchor),
            disabledSlotProgressIndicator.centerXAnchor.constraint(equalTo: disabledProgressContainer.centerXAnchor),
            disabledSlotProgressIndicator.centerYAnchor.constraint(equalTo: disabledProgressContainer.centerYAnchor)
        ])
    }

    private func setupSpacer() {
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    }

    private func applyConfiguration() {
        guard let configuration else {
            return
        }

        if configuration.areControlsDisabled {
            closePlusMenu()
            closeReasoningMenu()
            closeWorktreeLocationMenu()
        }
        if configuration.areControlsDisabled || configuration.supportedPermissionModes.isEmpty {
            closePermissionMenu()
        }
        if configuration.areControlsDisabled || !configuration.showWorktreePicker {
            closeWorktreeLocationMenu()
        }
        applyMenuConfiguration(configuration)
        applyPlusButtonConfiguration(configuration)
        applyAccessoryConfiguration(configuration)
        applyActionConfiguration(configuration)
        rebuildArrangedSubviews(configuration)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func applyMenuConfiguration(_ configuration: Configuration) {
        let option = ChatComposerWorktreeLocationPresentation.selectedOption(
            usesWorktree: configuration.selectedUseWorktree
        )
        worktreeButton.configure(
            option: option,
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            actionHandler: { [weak self] in
                self?.toggleWorktreeLocationMenu()
            }
        )
        worktreeMenuController?.update(
            options: ChatComposerWorktreeLocationPresentation.options(),
            selectedValue: option.value
        )
    }

    private func applyAccessoryConfiguration(_ configuration: Configuration) {
        sessionLocationField.stringValue = configuration.sessionLocationLabel ?? ""
        sessionLocationField.toolTip = configuration.sessionLocationLabel

        contextIndicatorView.configure(summary: configuration.usageSummary)
    }

    private func applyActionConfiguration(_ configuration: Configuration) {
        let primaryActionIsEnabled: Bool
        if case .idle = configuration.mode {
            primaryActionIsEnabled = !configuration.isPrimaryActionDisabled
        } else {
            primaryActionIsEnabled = false
        }
        primaryButton.configure(
            title: configuration.primaryActionTitle,
            symbolName: configuration.primaryActionSystemImage,
            isEnabled: primaryActionIsEnabled,
            accessibilityLabel: configuration.primaryActionTitle
        )
        stopButton.configure(
            title: configuration.isStopConfirmationArmed ? "Confirm" : "Stop",
            symbolName: "stop.fill",
            isEnabled: true,
            accessibilityLabel: configuration.isStopConfirmationArmed ? "Confirm stop" : "Stop"
        )
        disabledSendSlot.configure(
            title: "Send",
            symbolName: "paperplane.fill",
            isEnabled: false,
            accessibilityLabel: "Sending message",
            hidesContent: true
        )
        progressStackHeightConstraint?.constant = configuration.composerActionRowHeight
        progressLabel.stringValue = progressLabelText(for: configuration)
    }

    private func rebuildArrangedSubviews(_ configuration: Configuration) {
        let nextSubviews = arrangedSubviews(for: configuration)
        rowSubviews
            .filter { oldView in !nextSubviews.contains { $0 === oldView } }
            .forEach { $0.removeFromSuperview() }
        for view in nextSubviews where view.superview !== stack {
            stack.addSubview(view)
        }
        rowSubviews = nextSubviews
    }

    private func arrangedSubviews(for configuration: Configuration) -> [NSView] {
        var views: [NSView] = []
        views.append(plusButton)
        if !configuration.supportedPermissionModes.isEmpty {
            views.append(permissionButton)
        }
        if configuration.showWorktreePicker {
            views.append(worktreeButton)
        } else if configuration.sessionLocationLabel != nil {
            views.append(sessionLocationField)
        }

        views.append(spacer)
        if configuration.usageSummary != nil {
            views.append(contextIndicatorView)
        }
        // Keep reasoning pinned between optional context usage and the action slot.
        views.append(reasoningButton)
        switch configuration.mode {
        case .idle:
            views.append(primaryButton)
        case .busy(let canStop):
            views.append(canStop ? stopButton : disabledProgressContainer)
        case .progressOnly(let reason):
            if reason.canStop {
                views.append(stopButton)
            } else {
                if reason != .reconfiguringSession {
                    views.append(progressStack)
                }
                views.append(primaryButton)
            }
        }
        return views
    }

}
