import AppKit
import SwiftUI
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
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

    func testReplacingTextAppendsTrailingSpaceForSlashCommandAtEndOfText() {
        let text = "/revi"
        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: text,
            offsets: 0..<5,
            with: "/review-github-pr",
            appendTrailingSpace: true
        )

        XCTAssertEqual(newText, "/review-github-pr ")
        XCTAssertEqual(insertionOffset, 18)
    }

    func testReplacingTextAppendsTrailingSpaceForFileMentionAtEndOfText() {
        let text = "@Chat"
        let (newText, insertionOffset) = ChatInputFieldTextSupport.replacingText(
            in: text,
            offsets: 0..<5,
            with: "@Alveary/Views/Input/ChatInputField.swift",
            appendTrailingSpace: true
        )

        XCTAssertEqual(newText, "@Alveary/Views/Input/ChatInputField.swift ")
        XCTAssertEqual(insertionOffset, 42)
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

    func testComposerTextChipsUseFilenameDisplayForFileMentions() {
        let text = "/review-github-pr inspect @/tmp/alveary/Alveary/Views/Input/ChatInputField.swift next"
        guard let mentionRange = text.range(of: "@/tmp/alveary/Alveary/Views/Input/ChatInputField.swift"),
              let mentionLowerOffset = ChatInputFieldTextSupport.offset(of: mentionRange.lowerBound, in: text),
              let mentionUpperOffset = ChatInputFieldTextSupport.offset(of: mentionRange.upperBound, in: text) else {
            return XCTFail("Expected mention range")
        }

        let chips = ChatInputFieldTextSupport.composerTextChips(in: text)

        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0], AppTextEditorChip(range: NSRange(location: 0, length: 17), displayText: "/review-github-pr", style: .slashCommand))
        XCTAssertEqual(
            chips[1],
            AppTextEditorChip(
                range: NSRange(location: mentionLowerOffset, length: mentionUpperOffset - mentionLowerOffset),
                displayText: "@ChatInputField.swift",
                style: .fileMention
            )
        )
    }

    func testComposerTextChipsIgnoreMentionsInsideInlineCode() {
        let chips = ChatInputFieldTextSupport.composerTextChips(
            in: "Inspect `@Alveary/Views/Input/ChatInputField.swift` next"
        )

        XCTAssertTrue(chips.isEmpty)
    }

    func testEffortLabelsUseBareLevelNames() {
        XCTAssertEqual(ChatInputFieldTextSupport.effortLabel(for: "low"), "Low")
        XCTAssertEqual(ChatInputFieldTextSupport.effortLabel(for: "medium"), "Medium")
        XCTAssertEqual(ChatInputFieldTextSupport.effortLabel(for: "high"), "High")
        XCTAssertEqual(ChatInputFieldTextSupport.effortLabel(for: "max"), "Max")
    }

    func testPermissionModeLabelsUseFriendlyNames() {
        XCTAssertEqual(ChatInputFieldTextSupport.permissionModeLabel(for: "default"), "Default")
        XCTAssertEqual(ChatInputFieldTextSupport.permissionModeLabel(for: "plan"), "Plan")
        XCTAssertEqual(ChatInputFieldTextSupport.permissionModeLabel(for: "acceptEdits"), "Accept edits")
        XCTAssertEqual(ChatInputFieldTextSupport.permissionModeLabel(for: "auto"), "Automatic")
    }

    func testWorktreeLocationLabelsUseFriendlyNames() {
        XCTAssertEqual(ChatInputFieldTextSupport.worktreeLocationLabel(for: false), "Local")
        XCTAssertEqual(ChatInputFieldTextSupport.worktreeLocationLabel(for: true), "Worktree")
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

    func testInlineSlashCommandHintShowsAtEndOfExactCommand() {
        let text = "/review-github-pr "

        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: TextSelection(insertionPoint: text.endIndex),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertEqual(hint, "[PR URL]")
    }

    func testInlineSlashCommandHintPrefixesSpaceBeforeArgumentsStart() {
        let text = "/review-github-pr"

        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: TextSelection(insertionPoint: text.endIndex),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertEqual(hint, " [PR URL]")
    }

    func testInlineSlashCommandHintHidesOnceArgumentsBegin() {
        let text = "/review-github-pr https://github.com/example/repo/pull/42"

        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: TextSelection(insertionPoint: text.endIndex),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertNil(hint)
    }

    func testInlineSlashCommandHintHidesWhenCaretLeavesEndOfCommand() {
        let text = "/review-github-pr "
        let caretIndex = text.index(before: text.endIndex)

        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: TextSelection(insertionPoint: caretIndex),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertNil(hint)
    }

    func testInlineSlashCommandHintHidesForSelectionRanges() {
        let text = "/review-github-pr "

        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: TextSelection(range: text.startIndex..<text.endIndex),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertNil(hint)
    }

    func testInlineSlashCommandHintHidesAfterTrailingNewline() {
        let text = "/review-github-pr\n"

        let hint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: text,
            textSelection: TextSelection(insertionPoint: text.endIndex),
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertNil(hint)
    }

    func testInlineSlashCommandHintSurvivesStaleSelectionWhileFocused() {
        let staleText = "/review-github-pr extra"
        let staleSelection = TextSelection(
            insertionPoint: staleText.index(staleText.startIndex, offsetBy: staleText.count)
        )

        let focusedHint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: "/review-github-pr",
            textSelection: staleSelection,
            isInputFocused: true,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertEqual(focusedHint, " [PR URL]")

        let unfocusedHint = ChatInputFieldTextSupport.inlineSlashCommandHint(
            in: "/review-github-pr",
            textSelection: staleSelection,
            isInputFocused: false,
            commandHints: ["review-github-pr": "[PR URL]"]
        )

        XCTAssertNil(unfocusedHint)
    }

    func testInlineHintDrawingRectStartsAfterCommandText() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "/review-github-pr "

        guard let hintRect = textView.inlineHintDrawingRect() else {
            return XCTFail("Expected inline hint drawing rect")
        }

        XCTAssertGreaterThan(hintRect.minX, textView.textContainerInset.width)
        XCTAssertEqual(hintRect.minY, textView.textContainerOrigin.y)
    }

    func testComposerAutocompleteMatcherFiltersFileSuggestionsForNarrowQuery() {
        let files = [
            "Alveary/Views/Input/ChatInputAutocomplete.swift",
            "Alveary/Views/Input/ChatInputField.swift",
            "Alveary/Views/Chat/ChatView.swift"
        ]

        let result = ComposerAutocompleteMatcher.matches(
            for: .file,
            query: "autocomplete",
            source: .file(files, workingDirectory: nil),
            limit: 10
        )

        XCTAssertEqual(
            result.suggestions.map(\.id),
            ["Alveary/Views/Input/ChatInputAutocomplete.swift"]
        )
        XCTAssertEqual(result.totalMatches, 1)
    }

    func testRefreshInlineHintViewAddsVisibleLabel() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "/review-github-pr"
        textView.inlineHint = AppTextEditorInlineHint(text: " [PR URL]")

        textView.refreshInlineHintView()

        let hintViews = textView.subviews.compactMap { $0 as? AppTextEditorInlineHintView }
        XCTAssertEqual(hintViews.count, 1)
        XCTAssertEqual(hintViews.first?.text, " [PR URL]")
        XCTAssertEqual(hintViews.first?.isHidden, false)
    }

    func testArgumentHintsByCommandKeyKeepsFirstDuplicateNameAndIndexesIDs() {
        let hints = ChatInputField.argumentHintsByCommandKey(from: [
            Skill(
                id: "review-github-pr-local",
                name: "review-github-pr",
                description: "Local",
                argumentHint: "[LOCAL PR URL]",
                version: nil,
                source: .local,
                isInstalled: true,
                syncedAgentIDs: [],
                owner: nil,
                repo: nil,
                sourceUrl: nil,
                installs: nil
            ),
            Skill(
                id: "review-github-pr-remote",
                name: "review-github-pr",
                description: "Remote",
                argumentHint: "[REMOTE PR URL]",
                version: nil,
                source: .catalog,
                isInstalled: false,
                syncedAgentIDs: [],
                owner: nil,
                repo: nil,
                sourceUrl: nil,
                installs: nil
            )
        ])

        XCTAssertEqual(hints["review-github-pr"], "[LOCAL PR URL]")
        XCTAssertEqual(hints["review-github-pr-local"], "[LOCAL PR URL]")
        XCTAssertEqual(hints["review-github-pr-remote"], "[REMOTE PR URL]")
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

    func testTextChipDisplayModeFallsBackToFullTextWhileEditingMention() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "Inspect @Alveary/Views/Input/ChatInputField.swift next"

        let chip = AppTextEditorChip(
            range: NSRange(location: 8, length: 41),
            displayText: "@ChatInputField.swift",
            style: .fileMention
        )
        textView.textChips = [chip]

        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .compactLabel("@ChatInputField.swift"))

        textView.setSelectedRange(NSRange(location: 20, length: 0))

        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .fullText)
    }
}
