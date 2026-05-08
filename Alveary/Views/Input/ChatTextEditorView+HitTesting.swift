import AppKit

extension ChatTextEditorView {
    func claimTextFocus() {
        guard textView.isEditable || textView.isSelectable else {
            return
        }
        window?.makeFirstResponder(textView)
    }

    var hasTextFocus: Bool {
        window?.firstResponder === textView
    }

    func focusTextViewForMouseDown(_ event: NSEvent) {
        let textView = textViewForHitTesting
        textView.primeTextLayoutForInteraction()
        claimTextFocus()
        textView.mouseDown(with: event)
    }
}
