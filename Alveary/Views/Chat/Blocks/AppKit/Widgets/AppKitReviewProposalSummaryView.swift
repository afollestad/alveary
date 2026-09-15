import AppKit

/// The saved review body and its optional editing session. Typing never changes transcript configuration.
@MainActor
final class AppKitReviewProposalSummaryView: NSView {
    struct Configuration: Equatable {
        let proposalID: String?
        let markdown: String
        let document: AppMarkdownDocument?
        let isEditable: Bool
        let typography: TranscriptTypography
    }

    var onSave: ((String, String) -> Bool)?
    var onHeightInvalidated: (() -> Void)?
    var onEditingChanged: (() -> Void)?
    var onOpenLink: ((URL) -> Void)?
    private(set) var editor: AppKitMarkdownEditor?
    var isEditing: Bool { editor != nil }

    /// Fixed while editing so the current keystroke cannot widen the surrounding bubble.
    var naturalWidth: CGFloat { editorWidth ?? displayWidth }

    private let stack = NSStackView()
    private let actions = NSStackView()
    private var markdownView: AppKitMarkdownView?
    private var configuration: Configuration?
    private var editorWidth: CGFloat?
    private var displayWidth: CGFloat = 0
    private var renderedDocument: AppMarkdownDocument?
    private var renderedTypography: TranscriptTypography?
    private var heightInvalidationScheduled = false

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
        actions.orientation = .horizontal
        actions.spacing = 8
        stack.addArrangedSubview(actions)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func configure(_ configuration: Configuration) {
        guard self.configuration != configuration else { return }
        let prior = self.configuration
        self.configuration = configuration
        if prior?.proposalID != configuration.proposalID { endEditing() }
        if let editor, prior?.markdown != configuration.markdown, !editor.draft.hasChanges {
            endEditing()
            beginEditing()
        }
        editor?.setEditable(configuration.isEditable)
        updateDisplay()
        updateActions()
    }

    @objc func beginEditing() {
        guard editor == nil, let configuration, configuration.isEditable else { return }
        let width = max(bounds.width, 280)
        editorWidth = width
        let editor = AppKitMarkdownEditor(draft: AppMarkdownDraft(markdown: configuration.markdown), width: width)
        self.editor = editor
        editor.onSubmit = { [weak self] in self?.save() }
        editor.onCancel = { [weak self] in self?.cancel() }
        editor.onHeightInvalidated = { [weak self] in self?.scheduleHeightInvalidation() }
        stack.addFullWidthArrangedSubview(editor)
        stack.removeArrangedSubview(editor)
        stack.insertArrangedSubview(editor, at: 0)
        markdownView?.isHidden = true
        updateActions()
        onEditingChanged?()
        onHeightInvalidated?()
        DispatchQueue.main.async { [weak editor] in editor?.inputView.focusEditor() }
    }

    @objc func save() {
        guard let configuration, configuration.isEditable, let proposalID = configuration.proposalID,
              let editor, onSave?(proposalID, editor.draft.markdown) == true else { return }
        endEditing()
        updateDisplay()
        updateActions()
        onEditingChanged?()
        onHeightInvalidated?()
    }

    @objc func cancel() {
        guard configuration?.isEditable == true else { return }
        endEditing()
        updateDisplay()
        updateActions()
        onEditingChanged?()
        onHeightInvalidated?()
    }

    @objc private func clear() {
        guard let configuration, configuration.isEditable, let proposalID = configuration.proposalID else { return }
        _ = onSave?(proposalID, "")
    }

    /// Text layout may discover a new height while its parent is measuring. Defer the row callback.
    private func scheduleHeightInvalidation() {
        guard !heightInvalidationScheduled else { return }
        heightInvalidationScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            heightInvalidationScheduled = false
            onHeightInvalidated?()
        }
    }

    private func endEditing() {
        if let editor {
            stack.removeArrangedSubview(editor)
            editor.removeFromSuperview()
        }
        editor = nil
        editorWidth = nil
    }

    private func updateDisplay() {
        guard let configuration else { return }
        if configuration.markdown.isEmpty {
            if let markdownView {
                stack.removeArrangedSubview(markdownView)
                markdownView.removeFromSuperview()
                self.markdownView = nil
            }
            renderedDocument = nil
            displayWidth = 0
        }
        if let document = configuration.document, !configuration.markdown.isEmpty {
            if markdownView == nil {
                let view = AppKitMarkdownView(document: document, typography: Self.typography(configuration.typography))
                view.onOpenLink = { [weak self] url in self?.onOpenLink?(url) }
                view.onHeightInvalidated = { [weak self] in self?.scheduleHeightInvalidation() }
                markdownView = view
                stack.addFullWidthArrangedSubview(view)
                stack.removeArrangedSubview(view)
                stack.insertArrangedSubview(view, at: 0)
            }
            if renderedDocument != document || renderedTypography != configuration.typography {
                markdownView?.configure(document: document, typography: Self.typography(configuration.typography))
                renderedDocument = document
                renderedTypography = configuration.typography
                // A bounded preferred width, computed once per content/style update, never while scrolling.
                displayWidth = min(AppKitReviewProposalWidgetView.maximumDiffWidth,
                                   max(280, markdownView?.fittingSize.width ?? 0))
            }
        }
        markdownView?.isHidden = isEditing || configuration.markdown.isEmpty || configuration.document == nil
    }

    private func updateActions() {
        guard let configuration else { return }
        actions.arrangedSubviews.forEach { actions.removeArrangedSubview($0); $0.removeFromSuperview() }
        actions.isHidden = configuration.proposalID == nil
        guard !actions.isHidden else { return }
        if isEditing {
            addButton("Cancel edit", icon: .system("xmark"), action: #selector(cancel))
            addButton("Save comment", icon: .system("checkmark"), action: #selector(save))
        } else {
            addButton(
                configuration.markdown.isEmpty ? "Add comment" : "Edit", icon: .system("pencil"),
                action: #selector(beginEditing), isInline: configuration.markdown.isEmpty
            )
            if !configuration.markdown.isEmpty { addButton("Clear", icon: .system("xmark"), action: #selector(clear)) }
        }
    }

    private func addButton(_ title: String, icon: ActionIcon, action: Selector, isInline: Bool = false) {
        let button = AppKitTranscriptApprovalButton()
        button.title = title
        button.icon = isInline ? nil : icon
        button.actionStyle = .secondary
        if isInline {
            button.font = configuration?.typography.nsFont(.caption)
            button.inlineForegroundColor = AppAccentIcon.foregroundNSColor
            button.focusRingType = .exterior
        }
        button.controlSize = .small
        button.isBordered = false
        button.target = self
        button.action = action
        button.isEnabled = configuration?.isEditable == true
        button.setAccessibilityLabel(title == "Edit" ? "Edit review comment" : title)
        actions.addArrangedSubview(button)
    }

    private static func typography(_ typography: TranscriptTypography) -> AppKitMarkdownTypography {
        AppKitMarkdownTypography(
            title1: typography.nsFont(.headline, weight: .semibold),
            title2: typography.nsFont(.headline, weight: .semibold),
            headline: typography.nsFont(.body, weight: .semibold),
            subheadline: typography.nsFont(.toolSummary, weight: .semibold),
            body: typography.nsFont(.toolSummary),
            codeBlock: typography.inlineToolCodeNSFont,
            inlineCode: typography.inlineToolCodeNSFont
        )
    }
}
