import AppKit

/// Body for `propose_scheduled_task`: any blocking message plus whichever actions
/// apply to the proposal's current state.
///
/// Editing happens in the shared scheduled-task editor pane, so the row stays a
/// compact status block rather than a second form.
@MainActor
final class AppKitScheduledTaskProposalWidgetView: NSView {
    struct Configuration: Equatable {
        let content: ScheduledTaskProposalWidgetContent
        let presentation: ScheduledTaskProposalPresentation?
        let isInteractive: Bool
        let scheduledTaskID: String?
        let isResolving: Bool
        let outcome: HostToolWidgetOutcome?
        let errorMessage: String?
        let typography: TranscriptTypography
    }

    var onConfirm: ((String) -> Void)?
    var onReview: ((String) -> Void)?
    var onReject: ((String) -> Void)?
    /// Opens the resulting scheduled task, or the Scheduled screen when the widget could
    /// not resolve one.
    var onOpenScheduledTask: ((String?) -> Void)?

    private let stack = NSStackView()
    private var configuration: Configuration?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    var hasContent: Bool {
        !stack.arrangedSubviews.isEmpty
    }

    /// Widest row at its uncompressed size, so the shell can size to content. The
    /// actions row carries a flexible spacer, so measure its buttons instead.
    var naturalWidth: CGFloat {
        stack.arrangedSubviews.reduce(CGFloat.zero) { widest, row in
            guard let rowStack = row as? NSStackView else {
                return max(widest, ceil(row.fittingSize.width))
            }
            let buttons = rowStack.arrangedSubviews.filter { $0 is AppKitTranscriptApprovalButton }
            guard !buttons.isEmpty else {
                return max(widest, ceil(row.fittingSize.width))
            }
            let spacing = rowStack.spacing * CGFloat(buttons.count - 1)
            let width = buttons.reduce(CGFloat.zero) { $0 + ceil($1.fittingSize.width) } + spacing
            return max(widest, width)
        }
    }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else {
            return
        }
        self.configuration = configuration
        rebuild(configuration)
    }

    @objc
    private func handleConfirm() {
        guard let proposalID = configuration?.presentation?.id else {
            return
        }
        onConfirm?(proposalID)
    }

    @objc
    private func handleReview() {
        guard let proposalID = configuration?.presentation?.id else {
            return
        }
        onReview?(proposalID)
    }

    @objc
    private func handleReject() {
        guard let proposalID = configuration?.presentation?.id else {
            return
        }
        onReject?(proposalID)
    }

    @objc
    private func handleOpenScheduledTask() {
        onOpenScheduledTask?(configuration?.scheduledTaskID)
    }
}

private extension AppKitScheduledTaskProposalWidgetView {
    func rebuild(_ configuration: Configuration) {
        stack.arrangedSubviews.forEach { view in
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        for message in bannerMessages(configuration) {
            stack.addFullWidthArrangedSubview(
                AppKitTranscriptWidgetLabelFactory.label(
                    message,
                    level: .caption,
                    color: .systemRed,
                    typography: configuration.typography,
                    wraps: true
                )
            )
        }

        if let actions = actionRow(configuration) {
            stack.addFullWidthArrangedSubview(actions)
        }
    }

    func bannerMessages(_ configuration: Configuration) -> [String] {
        var messages: [String] = []
        if configuration.isInteractive, let conflictMessage = configuration.presentation?.conflictMessage {
            messages.append(conflictMessage)
        }
        if configuration.isInteractive, let errorMessage = configuration.errorMessage {
            messages.append(errorMessage)
        }
        if configuration.content.status == .failed, let message = configuration.content.message {
            messages.append(message)
        }
        return messages
    }

    func actionRow(_ configuration: Configuration) -> NSView? {
        guard let buttons = actionButtons(configuration), !buttons.isEmpty else {
            return nil
        }
        let row = NSStackView(views: buttons)
        row.translatesAutoresizingMaskIntoConstraints = false
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 8
        // A lone action has nothing to sit beside, so it spans the card instead of
        // leaving an arbitrary gap; a pair keeps its natural widths.
        if buttons.count == 1 {
            row.distribution = .fillEqually
            buttons.forEach { $0.setContentHuggingPriority(.defaultLow, for: .horizontal) }
        }
        return row
    }

    func actionButtons(_ configuration: Configuration) -> [NSView]? {
        guard configuration.isInteractive, let presentation = configuration.presentation else {
            return resolvedButtons(configuration)
        }

        let reject = button(
            title: "Cancel",
            icon: .system("xmark"),
            style: .secondary,
            action: #selector(handleReject)
        )
        reject.isEnabled = !configuration.isResolving

        // Create and edit carry a full definition, so they are reviewed in the shared
        // editor pane; the remaining actions have nothing to edit and confirm in place.
        // The summary line already names the action, so the buttons stay generic, and
        // the primary leads like the tool-approval blocks' Approve-then-Deny order.
        let isEditorProposal = configuration.content.isEditorProposal
        let primary = button(
            title: isEditorProposal ? "Review…" : "Confirm",
            icon: isEditorProposal ? .system("pencil") : .system("checkmark"),
            style: .primary,
            action: isEditorProposal ? #selector(handleReview) : #selector(handleConfirm)
        )
        primary.isEnabled = !configuration.isResolving &&
            (isEditorProposal || presentation.conflictMessage == nil)
        return [primary, reject]
    }

    func resolvedButtons(_ configuration: Configuration) -> [NSView]? {
        let didTakeEffect = configuration.outcome == .confirmed || configuration.content.status == .applied
        guard didTakeEffect, configuration.content.action != .delete else {
            return nil
        }
        let title = configuration.scheduledTaskID == nil ? "Open in Scheduled" : "View scheduled task"
        // The sidebar's Scheduled row glyph, since both open that surface.
        return [
            button(
                title: title,
                icon: .system("clock"),
                style: .secondary,
                action: #selector(handleOpenScheduledTask)
            )
        ]
    }

    func button(
        title: String,
        icon: ActionIcon,
        style: AppKitTranscriptApprovalButtonStyle,
        action: Selector
    ) -> AppKitTranscriptApprovalButton {
        let button = AppKitTranscriptApprovalButton()
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.title = title
        button.icon = icon
        button.actionStyle = style
        button.target = self
        button.action = action
        return button
    }
}
