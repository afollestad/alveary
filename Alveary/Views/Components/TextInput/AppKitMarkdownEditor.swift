import AppKit
import BlockInputKit

/// Native host for a single editing session. Configuration changes preserve its store and undo history.
@MainActor
final class AppKitMarkdownEditor: NSView {
    let draft: AppMarkdownDraft
    let inputView = BlockInputView()
    var onHeightInvalidated: (() -> Void)?
    var onSubmit: (() -> Void)?
    var onCancel: (() -> Void)?

    private let undoController = BlockInputUndoController()
    private var isEditable = true
    private var heightConstraint: NSLayoutConstraint?
    private var pendingHeight: CGFloat?
    private var isHeightUpdateScheduled = false
    private var measuredWidth: CGFloat = 0

    init(draft: AppMarkdownDraft, width: CGFloat) {
        self.draft = draft
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        inputView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(inputView)
        let height = inputView.heightAnchor.constraint(equalToConstant: 60)
        heightConstraint = height
        NSLayoutConstraint.activate([
            inputView.leadingAnchor.constraint(equalTo: leadingAnchor),
            inputView.trailingAnchor.constraint(equalTo: trailingAnchor),
            inputView.topAnchor.constraint(equalTo: topAnchor),
            inputView.bottomAnchor.constraint(equalTo: bottomAnchor),
            height
        ])
        inputView.setAccessibilityLabel("Review summary comment")
        configureInput()
        height.constant = inputView.preferredHeight(forWidth: width)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        guard bounds.width > 0, abs(bounds.width - measuredWidth) > 0.5 else { return }
        measuredWidth = bounds.width
        scheduleHeight(inputView.preferredHeight(forWidth: bounds.width))
    }

    func setEditable(_ editable: Bool) {
        guard isEditable != editable else { return }
        isEditable = editable
        configureInput()
    }

    private func configureInput() {
        inputView.configure(AppMarkdownEditorConfiguration.make(
            draft: draft, placeholder: "Leave a comment", isEditable: isEditable,
            undoController: undoController,
            onSubmit: { [weak self] in self?.onSubmit?() },
            onCancel: { [weak self] in self?.onCancel?() },
            onHeightChange: { [weak self] height in self?.scheduleHeight(height) }
        ))
    }

    /// Coalesce SDK callbacks outside measurement; capped typing leaves the transcript untouched.
    private func scheduleHeight(_ height: CGFloat) {
        pendingHeight = ceil(height)
        guard !isHeightUpdateScheduled else { return }
        isHeightUpdateScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            isHeightUpdateScheduled = false
            guard let height = pendingHeight, let heightConstraint,
                  abs(heightConstraint.constant - height) > 0.5 else { return }
            heightConstraint.constant = height
            invalidateIntrinsicContentSize()
            onHeightInvalidated?()
        }
    }
}
