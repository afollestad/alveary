import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
final class AppKitTextEditorCoordinatorTests: XCTestCase {
    func testActiveCompletionTokenReturnsNilForStaleSelectionAfterTextReset() {
        let staleText = "@file"
        let staleSelection = TextSelection(
            insertionPoint: staleText.index(staleText.startIndex, offsetBy: staleText.count)
        )

        let token = ChatInputFieldTextSupport.activeCompletionToken(
            text: "",
            textSelection: staleSelection
        )

        XCTAssertNil(token)
    }

    func testEditableSelectionOffsetsReturnNilForStaleSelectionAfterTextReset() {
        let staleText = "@file"
        let staleSelection = TextSelection(
            range: staleText.startIndex..<staleText.endIndex
        )

        let offsets = ChatInputFieldTextSupport.editableSelectionOffsets(
            text: "",
            textSelection: staleSelection
        )

        XCTAssertNil(offsets)
    }

    func testActiveCompletionTokenHandlesUTF16OffsetsBeforeEmojiPrefixedMention() {
        let text = "Prep 😀 @file next"
        guard let mentionRange = text.range(of: "@file") else {
            return XCTFail("Expected mention range")
        }

        guard let token = ChatInputFieldTextSupport.activeCompletionToken(
            text: text,
            textSelection: TextSelection(insertionPoint: mentionRange.upperBound)
        ) else {
            return XCTFail("Expected active completion token")
        }
        guard let lowerOffset = ChatInputFieldTextSupport.offset(of: mentionRange.lowerBound, in: text),
              let upperOffset = ChatInputFieldTextSupport.offset(of: mentionRange.upperBound, in: text) else {
            return XCTFail("Expected UTF-16 offsets")
        }
        let expectedRange = lowerOffset..<upperOffset

        XCTAssertEqual(token.kind, ComposerAutocompleteKind.file)
        XCTAssertEqual(token.query, "file")
        XCTAssertEqual(token.replacementOffsets, expectedRange)
    }

    func testReplacingTextTracksUTF16InsertionOffsetAfterEmojiPrefix() {
        let text = "Prep 😀 @fi tail"
        guard let mentionRange = text.range(of: "@fi"),
              let lowerOffset = ChatInputFieldTextSupport.offset(of: mentionRange.lowerBound, in: text),
              let upperOffset = ChatInputFieldTextSupport.offset(of: mentionRange.upperBound, in: text) else {
            return XCTFail("Expected mention offsets")
        }
        let replacementOffsets = lowerOffset..<upperOffset

        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: text,
            offsets: replacementOffsets,
            with: "@file",
            appendTrailingSpace: false
        )

        XCTAssertEqual(newText, "Prep 😀 @file tail")
        guard let newMentionRange = newText.range(of: "@file"),
              let expectedOffset = ChatInputFieldTextSupport.offset(of: newMentionRange.upperBound, in: newText) else {
            return XCTFail("Expected replacement offsets in updated text")
        }
        XCTAssertEqual(insertionOffset, expectedOffset)
    }

    func testHighlightedTokenRangesIncludeLeadingSlashCommandAndFileMentions() {
        let ranges = ChatInputFieldTextSupport.highlightedTokenRanges(
            in: "/ios-accessibility inspect @Alveary/Views/Input/ChatInputField.swift next"
        )

        XCTAssertEqual(ranges[0], NSRange(location: 0, length: 18))
        XCTAssertEqual(ranges[1], NSRange(location: 27, length: 41))
    }

    func testHighlightedTokenRangesIgnoreSlashCommandsAwayFromFront() {
        let ranges = ChatInputFieldTextSupport.highlightedTokenRanges(
            in: "Please run /ios-accessibility on @Alveary/Views/Input/ChatInputField.swift"
        )

        XCTAssertEqual(ranges, [NSRange(location: 33, length: 41)])
    }

    func testActiveCompletionTokenIgnoresColonPrefixedMentions() {
        let text = "See:@file"

        let token = ChatInputFieldTextSupport.activeCompletionToken(
            text: text,
            textSelection: TextSelection(insertionPoint: text.endIndex)
        )

        XCTAssertNil(token)
        XCTAssertTrue(ChatInputFieldTextSupport.fileMentionMatches(in: text).isEmpty)
    }

    func testFileMentionMatchesExcludePrefixFromHighlightRange() {
        let matches = ChatInputFieldTextSupport.fileMentionMatches(
            in: "Review (@Alveary/Views/Input/ChatInputField.swift) next"
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].range, NSRange(location: 7, length: 42))
        XCTAssertEqual(matches[0].highlightRange, NSRange(location: 8, length: 41))
        XCTAssertEqual(matches[0].path, "Alveary/Views/Input/ChatInputField.swift")
    }

    func testSyncSelectionIfNeededNormalizesStaleSelectionAfterTextReset() {
        var text = ""
        let staleText = "hello"
        var selection: TextSelection? = TextSelection(
            insertionPoint: staleText.index(staleText.startIndex, offsetBy: 3)
        )
        var measuredHeight: CGFloat = 0

        let parent = AppKitTextEditorView(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: Binding(get: { selection }, set: { selection = $0 }),
            measuredTextHeight: Binding(get: { measuredHeight }, set: { measuredHeight = $0 }),
            placeholder: nil,
            horizontalPadding: 10,
            verticalPadding: 10,
            isDisabled: false,
            focus: nil,
            textHighlightRanges: nil,
            keyPressKeys: [],
            onKeyPress: nil
        )

        let coordinator = AppKitTextEditorCoordinator(parent: parent)
        let textView = AppKitTextView(frame: .zero)
        textView.string = text
        let scrollView = AppKitTextEditorScrollView(frame: .zero)
        scrollView.documentView = textView
        coordinator.attach(textView: textView, scrollView: scrollView)

        coordinator.syncSelectionIfNeeded()

        XCTAssertEqual(
            ChatInputFieldTextSupport.insertionPointOffset(text: text, textSelection: selection),
            0
        )
        XCTAssertEqual(textView.selectedRange(), NSRange(location: 0, length: 0))
    }
}
