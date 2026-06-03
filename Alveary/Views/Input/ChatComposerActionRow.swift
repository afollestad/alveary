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
    let providerOptions: [ChatComposerActionRowView.MenuOption]
    @Binding var selectedProvider: String
    let modelOptions: [ChatComposerActionRowView.MenuOption]
    @Binding var selectedModel: String
    let supportedEffortLevels: [String]
    @Binding var selectedEffort: String
    let supportedPermissionModes: [PermissionModeOption]
    @Binding var selectedPermissionMode: String
    let showWorktreePicker: Bool
    @Binding var selectedUseWorktree: Bool
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
            providerOptions: providerOptions,
            selectedProvider: selectedProvider,
            modelOptions: modelOptions,
            selectedModel: selectedModel,
            supportedEffortLevels: supportedEffortLevels.map { .init(value: $0, title: ChatComposerTextSupport.effortLabel(for: $0)) },
            selectedEffort: selectedEffort,
            supportedPermissionModes: supportedPermissionModes.map {
                .init(value: $0.value, title: ChatComposerTextSupport.permissionModeLabel(for: $0))
            },
            selectedPermissionMode: selectedPermissionMode,
            showWorktreePicker: showWorktreePicker,
            selectedUseWorktree: selectedUseWorktree,
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
            onProviderChange: { selectedProvider = $0 },
            onModelChange: { selectedModel = $0 },
            onEffortChange: { selectedEffort = $0 },
            onPermissionModeChange: { selectedPermissionMode = $0 },
            onUseWorktreeChange: { selectedUseWorktree = $0 },
            onSubmit: onSubmit,
            onStop: onStop,
            onShowKeymap: onShowKeymap
        )
    }
}

/// Native bottom composer row for model/effort/permission/worktree selectors,
/// context/keymap accessories, and send/stop/progress action slots.
@MainActor
final class ChatComposerActionRowView: NSView {
    nonisolated static let defaultHeight: CGFloat = 30
    nonisolated static let defaultContextIndicatorKeyboardSpacing: CGFloat = 6

    struct MenuOption: Equatable {
        let value: String
        let title: String
    }

    struct Configuration {
        let providerOptions: [MenuOption]
        let selectedProvider: String
        let modelOptions: [MenuOption]
        let selectedModel: String
        let supportedEffortLevels: [MenuOption]
        let selectedEffort: String
        let supportedPermissionModes: [MenuOption]
        let selectedPermissionMode: String
        let showWorktreePicker: Bool
        let selectedUseWorktree: Bool
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
        let onProviderChange: (String) -> Void
        let onModelChange: (String) -> Void
        let onEffortChange: (String) -> Void
        let onPermissionModeChange: (String) -> Void
        let onUseWorktreeChange: (Bool) -> Void
        let onSubmit: () -> Void
        let onStop: () -> Void
        let onShowKeymap: () -> Void

    }

    private let providerMenu = ComposerMenuButton()
    private let modelMenu = ComposerMenuButton()
    private let effortMenu = ComposerMenuButton()
    private let permissionMenu = ComposerMenuButton()
    private let worktreeMenu = ComposerMenuButton()
    let sessionLocationField = NSTextField(labelWithString: "")
    // Internal so `ChatComposerActionRow+Layout.swift` can keep the overflow
    // frame logic out of this already-large view type without widening behavior.
    let spacer = NSView()
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
        providerMenu.setAccessibilityLabel("Provider")
        providerMenu.setMenuHeaderTitle("Provider")
        modelMenu.setAccessibilityLabel("Model")
        modelMenu.setMenuHeaderTitle("Model")
        effortMenu.setAccessibilityLabel("Effort")
        effortMenu.setMenuHeaderTitle("Effort")
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

        applyMenuConfiguration(configuration)
        applyAccessoryConfiguration(configuration)
        applyActionConfiguration(configuration)
        rebuildArrangedSubviews(configuration)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    private func applyMenuConfiguration(_ configuration: Configuration) {
        providerMenu.configure(
            title: title(for: configuration.selectedProvider, in: configuration.providerOptions),
            options: configuration.providerOptions,
            selectedValue: configuration.selectedProvider,
            isEnabled: !configuration.areControlsDisabled && configuration.providerOptions.count > 1,
            onSelect: configuration.onProviderChange
        )
        modelMenu.configure(
            title: title(for: configuration.selectedModel, in: configuration.modelOptions),
            options: configuration.modelOptions,
            selectedValue: configuration.selectedModel,
            isEnabled: !configuration.areControlsDisabled,
            onSelect: configuration.onModelChange
        )
        effortMenu.configure(
            title: title(for: configuration.selectedEffort, in: configuration.supportedEffortLevels),
            options: configuration.supportedEffortLevels,
            selectedValue: configuration.selectedEffort,
            isEnabled: !configuration.areControlsDisabled,
            onSelect: configuration.onEffortChange
        )
        permissionMenu.configure(
            title: title(for: configuration.selectedPermissionMode, in: configuration.supportedPermissionModes),
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

    private func applyAccessoryConfiguration(_ configuration: Configuration) {
        sessionLocationField.stringValue = configuration.sessionLocationLabel ?? ""
        sessionLocationField.toolTip = configuration.sessionLocationLabel

        contextIndicatorView.configure(summary: configuration.usageSummary)
        keyboardButton.isHidden = configuration.isTextEditorDisabled
    }

    private func applyActionConfiguration(_ configuration: Configuration) {
        primaryButton.configure(
            title: configuration.primaryActionTitle,
            symbolName: configuration.primaryActionSystemImage,
            isEnabled: !configuration.isPrimaryActionDisabled,
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
        rowSubviews.forEach { $0.removeFromSuperview() }
        rowSubviews = []

        addSettingsControls(for: configuration)
        addRowSubview(spacer)
        addAccessoryControls(for: configuration)
        addActionControls(for: configuration)
    }

    private func addSettingsControls(for configuration: Configuration) {
        if !configuration.providerOptions.isEmpty {
            addRowSubview(providerMenu)
        }
        addRowSubview(modelMenu)
        if !configuration.supportedEffortLevels.isEmpty {
            addRowSubview(effortMenu)
        }
        if !configuration.supportedPermissionModes.isEmpty {
            addRowSubview(permissionMenu)
        }
        if configuration.showWorktreePicker {
            addRowSubview(worktreeMenu)
        } else if configuration.sessionLocationLabel != nil {
            addRowSubview(sessionLocationField)
        }
    }

    private func addAccessoryControls(for configuration: Configuration) {
        guard configuration.usageSummary != nil || !configuration.isTextEditorDisabled else {
            return
        }

        let accessoryGroup = ChatComposerAccessoryGroupView(spacing: configuration.contextIndicatorKeyboardSpacing)
        if configuration.usageSummary != nil {
            accessoryGroup.addAccessory(contextIndicatorView)
        }
        if !configuration.isTextEditorDisabled {
            accessoryGroup.addAccessory(keyboardButton)
        }
        addRowSubview(accessoryGroup)
    }

    private func addActionControls(for configuration: Configuration) {
        switch configuration.mode {
        case .idle:
            addRowSubview(primaryButton)
        case .busy(let canStop):
            addRowSubview(canStop ? stopButton : disabledProgressSlot())
        case .progressOnly(let reason):
            if reason.canStop {
                addRowSubview(stopButton)
            } else {
                addRowSubview(progressStack)
            }
        }
    }

    private func addRowSubview(_ view: NSView) {
        rowSubviews.append(view)
        stack.addSubview(view)
    }

    private func disabledProgressSlot() -> NSView {
        disabledProgressContainer
    }

    private func title(for value: String, in options: [MenuOption]) -> String {
        options.first { $0.value == value }?.title ?? value
    }

    private func progressLabelText(for configuration: Configuration) -> String {
        guard case .progressOnly(let reason) = configuration.mode,
              !reason.canStop else {
            return ""
        }
        return ChatComposerTextSupport.progressLabel(for: reason)
    }
}
