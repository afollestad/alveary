@preconcurrency import AppKit

struct AppTextEditorInlineHint: Equatable {
    let text: String
}

final class AppTextEditorInlineHintView: NSView {
    var text = "" {
        didSet {
            needsDisplay = true
        }
    }

    var font: NSFont = .preferredFont(forTextStyle: .body) {
        didSet {
            needsDisplay = true
        }
    }

    var textColor: NSColor = .placeholderTextColor {
        didSet {
            needsDisplay = true
        }
    }

    override var isFlipped: Bool {
        true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        guard !text.isEmpty else {
            return
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor
        ]

        (text as NSString).draw(
            with: bounds.intersection(dirtyRect),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }
}

final class AppKitTextView: NSTextView {
    private lazy var inlineHintView: AppTextEditorInlineHintView = {
        let view = AppTextEditorInlineHintView(frame: .zero)
        view.isHidden = true
        return view
    }()

    var onFocusChange: ((Bool) -> Void)?
    var placeholder = "" {
        didSet {
            needsDisplay = true
        }
    }
    var inlineHint: AppTextEditorInlineHint? {
        didSet {
            updateInlineHintView()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        if string.isEmpty, !placeholder.isEmpty {
            drawPlaceholder(in: dirtyRect)
        }
        super.draw(dirtyRect)
    }

    override func didChangeText() {
        super.didChangeText()
        needsDisplay = true
        updateInlineHintView()
    }

    override func becomeFirstResponder() -> Bool {
        let didBecomeFirstResponder = super.becomeFirstResponder()
        if didBecomeFirstResponder {
            onFocusChange?(true)
            needsDisplay = true
            updateInlineHintView()
        }
        return didBecomeFirstResponder
    }

    override func resignFirstResponder() -> Bool {
        let didResignFirstResponder = super.resignFirstResponder()
        if didResignFirstResponder {
            onFocusChange?(false)
            needsDisplay = true
            updateInlineHintView()
        }
        return didResignFirstResponder
    }

    override func layout() {
        super.layout()
        updateInlineHintView()
    }

    private func drawPlaceholder(in dirtyRect: NSRect) {
        let lineFragmentPadding = textContainer?.lineFragmentPadding ?? 0
        let placeholderRect = NSRect(
            x: textContainerInset.width + lineFragmentPadding,
            y: textContainerInset.height,
            width: max(bounds.width - (textContainerInset.width * 2) - (lineFragmentPadding * 2), 0),
            height: max(bounds.height - (textContainerInset.height * 2), 0)
        )

        let paragraphStyle = (typingAttributes[.paragraphStyle] as? NSParagraphStyle) ?? NSParagraphStyle.default
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font ?? .preferredFont(forTextStyle: .body),
            .foregroundColor: NSColor.placeholderTextColor,
            .paragraphStyle: paragraphStyle
        ]

        (placeholder as NSString).draw(
            with: placeholderRect.intersection(dirtyRect),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
        )
    }

    func refreshInlineHintView() {
        updateInlineHintView()
    }

    private func updateInlineHintView() {
        guard let inlineHint,
              !inlineHint.text.isEmpty,
              !string.isEmpty,
              let hintRect = inlineHintDrawingRect() else {
            inlineHintView.isHidden = true
            return
        }

        if inlineHintView.superview == nil {
            addSubview(inlineHintView)
        }

        inlineHintView.text = inlineHint.text
        inlineHintView.font = font ?? .preferredFont(forTextStyle: .body)
        inlineHintView.textColor = .placeholderTextColor
        inlineHintView.frame = hintRect.integral
        inlineHintView.isHidden = false
    }

    func inlineHintDrawingRect() -> NSRect? {
        guard let layoutManager,
               let textContainer else {
            return nil
        }

        layoutManager.ensureLayout(for: textContainer)
        let containerOrigin = textContainerOrigin
        let hintOrigin: CGPoint
        let lineHeight: CGFloat

        if let lineRect = inlineHintLineRect(using: layoutManager, textContainer: textContainer) {
            hintOrigin = CGPoint(
                x: containerOrigin.x + lineRect.maxX,
                y: containerOrigin.y + lineRect.minY
            )
            lineHeight = lineRect.height
        } else {
            let extraLineRect = layoutManager.extraLineFragmentUsedRect
            guard !extraLineRect.isEmpty else {
                return nil
            }
            hintOrigin = CGPoint(
                x: containerOrigin.x + extraLineRect.minX,
                y: containerOrigin.y + extraLineRect.minY
            )
            lineHeight = extraLineRect.height
        }

        return NSRect(
            x: hintOrigin.x,
            y: hintOrigin.y,
            width: max(bounds.width - hintOrigin.x - textContainerInset.width, 0),
            height: max(lineHeight, bounds.height - hintOrigin.y - textContainerInset.height)
        )
    }

    private func inlineHintLineRect(
        using layoutManager: NSLayoutManager,
        textContainer: NSTextContainer
    ) -> NSRect? {
        guard !string.isEmpty else {
            return nil
        }

        let textLength = (string as NSString).length
        let characterIndex = max(textLength - 1, 0)
        let glyphIndex = layoutManager.glyphIndexForCharacter(at: characterIndex)
        guard glyphIndex < layoutManager.numberOfGlyphs else {
            return nil
        }

        return layoutManager.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil, withoutAdditionalLayout: true)
    }
}
