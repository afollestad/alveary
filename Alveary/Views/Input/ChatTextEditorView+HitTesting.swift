import AppKit

extension ChatTextEditorView {
    func focusTextViewForMouseDown(_ event: NSEvent) {
        let textView = textViewForHitTesting
        textView.primeTextLayoutForInteraction()
        if textView.isEditable || textView.isSelectable {
            window?.makeFirstResponder(textView)
        }
        textView.mouseDown(with: event)
    }
}
