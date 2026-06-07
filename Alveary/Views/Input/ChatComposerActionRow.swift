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
    let isTextEditorDisabled: Bool
    let areControlsDisabled: Bool
    let mode: ComposerMode
    let primaryActionTitle: String
    let primaryActionSystemImage: String
    let isPrimaryActionDisabled: Bool
    let isStopConfirmationArmed: Bool
    let composerActionRowHeight: CGFloat
    let contextIndicatorKeyboardSpacing: CGFloat
    let onSubmit: () -> Void
    let onStop: () -> Void
    let onShowKeymap: () -> Void
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
            supportedPermissionModes: supportedPermissionModes.map {
                .init(value: $0.value, title: ChatComposerTextSupport.permissionModeLabel(for: $0))
            },
            selectedPermissionMode: selectedPermissionMode,
            showWorktreePicker: showWorktreePicker,
            selectedUseWorktree: selectedUseWorktree,
            isPlanModeEnabled: isPlanModeEnabled,
            isPlanModeToggleEnabled: isPlanModeToggleEnabled,
            planModeDisabledTooltip: planModeDisabledTooltip,
            sessionLocationLabel: sessionLocationLabel,
            usageSummary: usageSummary,
            isTextEditorDisabled: isTextEditorDisabled,
            areControlsDisabled: areControlsDisabled,
            mode: mode,
            primaryActionTitle: primaryActionTitle,
            primaryActionSystemImage: primaryActionSystemImage,
            isPrimaryActionDisabled: isPrimaryActionDisabled,
            isStopConfirmationArmed: isStopConfirmationArmed,
            composerActionRowHeight: composerActionRowHeight,
            contextIndicatorKeyboardSpacing: contextIndicatorKeyboardSpacing,
            onPermissionModeChange: { selectedPermissionMode = $0 },
            onUseWorktreeChange: { selectedUseWorktree = $0 },
            onPlanModeChange: { isPlanModeEnabled = $0 },
            onSubmit: onSubmit,
            onStop: onStop,
            onShowKeymap: onShowKeymap,
            onAddPhotosAndFiles: onAddPhotosAndFiles
        )
    }
}

/// Native bottom composer row for reasoning/permission/worktree selectors,
/// context/keymap accessories, and send/stop/progress action slots.
@MainActor
final class ChatComposerActionRowView: NSView {
    nonisolated static let defaultHeight: CGFloat = 30
    nonisolated static let defaultSettingsControlHeight: CGFloat = 24
    nonisolated static let defaultContextIndicatorKeyboardSpacing: CGFloat = 6

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
        let supportedPermissionModes: [MenuOption]
        let selectedPermissionMode: String
        let showWorktreePicker: Bool
        let selectedUseWorktree: Bool
        var isPlanModeEnabled = false
        var isPlanModeToggleEnabled = false
        var planModeDisabledTooltip: String?
        let sessionLocationLabel: String?
        let usageSummary: ConversationUsageSummary?
        let isTextEditorDisabled: Bool
        let areControlsDisabled: Bool
        let mode: ComposerMode
        let primaryActionTitle: String
        let primaryActionSystemImage: String
        let isPrimaryActionDisabled: Bool
        let isStopConfirmationArmed: Bool
        let composerActionRowHeight: CGFloat
        let contextIndicatorKeyboardSpacing: CGFloat
        let onPermissionModeChange: (String) -> Void
        let onUseWorktreeChange: (Bool) -> Void
        var onPlanModeChange: (Bool) -> Void = { _ in }
        let onSubmit: () -> Void
        let onStop: () -> Void
        let onShowKeymap: () -> Void
        var onAddPhotosAndFiles: () -> Void = {}
    }

    let plusButton = ComposerPlusButton()
    let reasoningButton = ComposerReasoningButton()
    private let permissionMenu = ComposerMenuButton()
    private let worktreeMenu = ComposerMenuButton()
    let sessionLocationField = NSTextField(labelWithString: "")
    // Internal so `ChatComposerActionRow+Layout.swift` can keep the overflow
    // frame logic out of this already-large view type without widening behavior.
    let spacer = NSView()
    private let accessoryGroup = ChatComposerAccessoryGroupView(spacing: ChatComposerActionRowView.defaultContextIndicatorKeyboardSpacing)
    private let contextIndicatorView = AppKitContextWindowIndicatorView()
    private let keyboardButton = ComposerIconButton(symbolName: "keyboard")
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
    private var progressStackHeightConstraint: NSLayoutConstraint?
    let rowSpacing: CGFloat = 10
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
        permissionMenu.setAccessibilityLabel("Permissions")
        permissionMenu.setMenuHeaderTitle("Permissions")
        worktreeMenu.setAccessibilityLabel("Thread location")
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
        keyboardButton.actionHandler = { [weak self] in
            self?.configuration?.onShowKeymap()
        }
        keyboardButton.setAccessibilityLabel("Show chat keyboard shortcuts")

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
        permissionMenu.configure(
            title: configuration.supportedPermissionModes.first {
                $0.value == configuration.selectedPermissionMode
            }?.title ?? configuration.selectedPermissionMode,
            options: configuration.supportedPermissionModes,
            selectedValue: configuration.selectedPermissionMode,
            isEnabled: !configuration.areControlsDisabled,
            onSelect: configuration.onPermissionModeChange
        )
        worktreeMenu.configure(
            title: ChatComposerTextSupport.worktreeLocationLabel(for: configuration.selectedUseWorktree),
            options: [
                .init(value: "false", title: ChatComposerTextSupport.worktreeLocationLabel(for: false)),
                .init(value: "true", title: ChatComposerTextSupport.worktreeLocationLabel(for: true))
            ],
            selectedValue: String(configuration.selectedUseWorktree),
            isEnabled: !configuration.areControlsDisabled,
            onSelect: { configuration.onUseWorktreeChange($0 == "true") }
        )
    }

    private func applyPlusButtonConfiguration(_ configuration: Configuration) {
        plusButton.configure(
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            actionHandler: { [weak self] in
                self?.togglePlusMenu()
            }
        )
        reasoningButton.configure(
            selection: configuration.reasoning.selection,
            height: Self.defaultSettingsControlHeight,
            isEnabled: !configuration.areControlsDisabled,
            showsProgress: configuration.isReconfiguringSession,
            actionHandler: { [weak self] in
                self?.toggleReasoningMenu()
            }
        )
        // Keep an open reasoning popup tied to the persisted provider/model/
        // effort state, including async reconfigure rollback updates.
        reasoningMenuController?.update(configuration: configuration.reasoning)
    }

    private func applyAccessoryConfiguration(_ configuration: Configuration) {
        sessionLocationField.stringValue = configuration.sessionLocationLabel ?? ""
        sessionLocationField.toolTip = configuration.sessionLocationLabel

        contextIndicatorView.configure(summary: configuration.usageSummary)
        keyboardButton.configure(isEnabled: !configuration.isTextEditorDisabled && !configuration.areControlsDisabled)
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
            views.append(permissionMenu)
        }
        if configuration.showWorktreePicker {
            views.append(worktreeMenu)
        } else if configuration.sessionLocationLabel != nil {
            views.append(sessionLocationField)
        }

        views.append(spacer)
        if let accessoryGroup = configuredAccessoryGroup(for: configuration) {
            views.append(accessoryGroup)
        }
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

    private func configuredAccessoryGroup(for configuration: Configuration) -> ChatComposerAccessoryGroupView? {
        var accessories: [NSView] = []
        if configuration.usageSummary != nil {
            accessories.append(contextIndicatorView)
        }
        // Keep reasoning pinned between context usage and keyboard help.
        accessories.append(reasoningButton)
        accessories.append(keyboardButton)
        accessoryGroup.configure(
            accessories: accessories,
            spacing: configuration.contextIndicatorKeyboardSpacing
        )
        return accessories.isEmpty ? nil : accessoryGroup
    }
}
