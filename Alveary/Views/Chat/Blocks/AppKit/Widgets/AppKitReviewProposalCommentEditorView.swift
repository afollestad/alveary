import AppKit

/// A published comment's inline edit: the markdown editor over the pane's Cancel and Update comment.
/// The comment card owns the session, so reconfiguring the card with the same comment keeps the text.
@MainActor
final class AppKitReviewProposalCommentEditorView: NSView {
    var onSave: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHeightInvalidated: (() -> Void)?

    let editor: AppKitMarkdownEditor

    private let cancelButton = AppKitTranscriptApprovalButton()
    private let saveButton = AppKitTranscriptApprovalButton()

    init(markdown: String, width: CGFloat) {
        editor = AppKitMarkdownEditor(draft: AppMarkdownDraft(markdown: markdown), width: width)
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        editor.inputView.setAccessibilityLabel("Review comment")
        editor.onSubmit = { [weak self] in self?.onSave?() }
        editor.onCancel = { [weak self] in self?.onCancel?() }
        editor.onHeightInvalidated = { [weak self] in self?.onHeightInvalidated?() }
        setup(cancelButton, icon: .system("xmark"), style: .secondary, action: #selector(cancel))
        setup(saveButton, icon: DiffCommentComposerMode.editRemote.saveIcon, style: .primary, action: #selector(save))
        setBusy(false)
        let actions = NSStackView(views: [NSView(), cancelButton, saveButton])
        actions.orientation = .horizontal
        actions.spacing = 6
        let stack = NSStackView()
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.addFullWidthArrangedSubview(editor)
        stack.addFullWidthArrangedSubview(actions)
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    var markdown: String { editor.draft.markdown }
    var hasChanges: Bool { editor.draft.hasChanges }

    /// While GitHub takes the edit, the text stays visible but frozen so a retry starts from it.
    func setBusy(_ isBusy: Bool) {
        editor.setEditable(!isBusy)
        cancelButton.isEnabled = !isBusy
        saveButton.isEnabled = !isBusy
        saveButton.title = isBusy ? "Updating…" : DiffCommentComposerMode.editRemote.saveTitle
    }

    func focus() {
        DispatchQueue.main.async { [weak editor] in editor?.inputView.focusEditor() }
    }

    @objc private func save() { onSave?() }
    @objc private func cancel() { onCancel?() }

    private func setup(
        _ button: AppKitTranscriptApprovalButton,
        icon: ActionIcon,
        style: AppKitTranscriptApprovalButtonStyle,
        action: Selector
    ) {
        button.translatesAutoresizingMaskIntoConstraints = false
        button.isBordered = false
        button.controlSize = .small
        button.title = "Cancel"
        button.icon = icon
        button.actionStyle = style
        button.target = self
        button.action = action
        button.setContentHuggingPriority(.required, for: .horizontal)
    }
}
