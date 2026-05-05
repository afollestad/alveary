import SwiftUI

extension ChatInputField {
    var composerTextEditor: some View {
        let activeFocusRequestToken = focusRequestToken
        return ChatTextEditor(
            text: $text,
            selection: $textSelection,
            minHeight: composerBaseHeight,
            idealHeight: composerBaseHeight,
            maxHeight: 144,
            placeholder: placeholder,
            cornerRadius: 18,
            cornerRadii: composerTextEditorCornerRadii,
            horizontalPadding: composerHorizontalPadding,
            verticalPadding: composerVerticalPadding,
            backgroundColor: Color.secondary.opacity(0.08),
            borderColor: inputBorderColor,
            borderWidth: inputBorderWidth,
            isDisabled: isTextEditorDisabled,
            showsDisabledCursor: isProjectTrustBlocked,
            focus: $isInputFocused,
            textChips: ChatInputFieldTextSupport.composerTextChips(in:),
            codeBlockRanges: AppMarkdownCodeBlockParser.blockRanges,
            inlineCodeBackgroundRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineContentRanges },
            inlineCodeDelimiterRanges: { AppMarkdownCodeBlockParser.codeRanges(in: $0).inlineDelimiterRanges },
            inlineHint: inlineSlashCommandHint,
            keyPressKeys: [.upArrow, .downArrow, .tab, .escape, .return],
            onKeyPress: handleKeyPress,
            requestFirstResponder: activeFocusRequestToken,
            onFocusRequestConsumed: {
                if Self.shouldClearFocusRequestToken(current: focusRequestToken, consumed: activeFocusRequestToken) {
                    focusRequestToken = nil
                }
            },
            isAppKitFirstResponder: $isComposerFirstResponder,
            disablesAppKitDragDestination: true
        )
        .overlay(alignment: .topLeading) {
            composerAutocompleteOverlay
        }
        .zIndex(activeAutocomplete == nil ? 0 : 1)
    }

    static func shouldClearFocusRequestToken(current: UUID?, consumed: UUID?) -> Bool {
        // Focus consumption comes back from the AppKit representable on the next
        // runloop; an older callback must not clear a newer focus request token.
        current == consumed
    }

    var composerTextEditorCornerRadii: RectangleCornerRadii? {
        guard !queuedMessages.isEmpty else {
            return nil
        }

        return RectangleCornerRadii(
            topLeading: 0,
            bottomLeading: 18,
            bottomTrailing: 18,
            topTrailing: 0
        )
    }

    @ViewBuilder
    var composerAutocompleteOverlay: some View {
        if let autocomplete = activeAutocomplete {
            let popupHeight = AppKitComposerAutocompletePopupView.measuredHeight(for: autocomplete)
            AppKitAutocompletePopupRepresentable(
                autocomplete: autocomplete,
                onSelect: applyAutocompleteSuggestion,
                onHighlight: highlightAutocompleteSuggestion
            )
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: popupHeight)
            .fixedSize(horizontal: false, vertical: true)
            .offset(y: -(popupHeight + 8))
            .zIndex(1)
        }
    }
}
