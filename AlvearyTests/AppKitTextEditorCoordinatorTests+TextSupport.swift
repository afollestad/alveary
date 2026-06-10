import AppKit
import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    func testComposerTextChipsStoreEncodedPathAndEncodedLastComponentForEncodedMention() {
        let text = "Inspect @/Users/me/My%20File.png now"
        let mentionRange = (text as NSString).range(of: "@/Users/me/My%20File.png")

        let chips = ChatComposerTextSupport.composerTextChips(in: text)

        XCTAssertEqual(chips.count, 1)
        XCTAssertEqual(
            chips[0],
            AppTextEditorChip(
                range: mentionRange,
                displayText: "@My%20File.png",
                style: .fileMention
            )
        )
    }

    func testComposerTextChipsUseFilenameDisplayForFileMentions() {
        let text = "/review-github-pr inspect @/tmp/alveary/Alveary/Views/Input/ChatView.swift next"
        let mentionRange = (text as NSString).range(of: "@/tmp/alveary/Alveary/Views/Input/ChatView.swift")

        let chips = ChatComposerTextSupport.composerTextChips(in: text)

        XCTAssertEqual(chips.count, 2)
        XCTAssertEqual(chips[0], AppTextEditorChip(range: NSRange(location: 0, length: 17), displayText: "/review-github-pr", style: .slashCommand))
        XCTAssertEqual(
            chips[1],
            AppTextEditorChip(
                range: mentionRange,
                displayText: "@ChatView.swift",
                style: .fileMention
            )
        )
    }

    func testComposerTextChipsIgnoreMentionsInsideInlineCode() {
        let chips = ChatComposerTextSupport.composerTextChips(
            in: "Inspect `@Alveary/Views/Chat/ChatView.swift` next"
        )

        XCTAssertTrue(chips.isEmpty)
    }

    func testModelLabelsUseFriendlyNames() {
        XCTAssertEqual(ChatComposerTextSupport.modelLabel(for: "default"), "Default")
        XCTAssertEqual(ChatComposerTextSupport.modelLabel(for: "fable"), "Fable")
        XCTAssertEqual(ChatComposerTextSupport.modelLabel(for: "opus"), "Opus")
        XCTAssertEqual(ChatComposerTextSupport.modelLabel(for: "sonnet"), "Sonnet")
        XCTAssertEqual(ChatComposerTextSupport.modelLabel(for: "haiku"), "Haiku")
        XCTAssertEqual(ChatComposerTextSupport.modelLabel(for: "custom-model"), "custom-model")
    }

    func testEffortLabelsUseBareLevelNames() {
        XCTAssertEqual(ChatComposerTextSupport.effortLabel(for: "low"), "Low")
        XCTAssertEqual(ChatComposerTextSupport.effortLabel(for: "medium"), "Medium")
        XCTAssertEqual(ChatComposerTextSupport.effortLabel(for: "high"), "High")
        XCTAssertEqual(ChatComposerTextSupport.effortLabel(for: "max"), "Max")
    }

    func testPermissionModeLabelsUseFriendlyNames() {
        XCTAssertEqual(ChatComposerTextSupport.permissionModeLabel(for: "default"), "Default")
        XCTAssertEqual(ChatComposerTextSupport.permissionModeLabel(for: "plan"), "Plan")
        XCTAssertEqual(ChatComposerTextSupport.permissionModeLabel(for: "acceptEdits"), "Accept edits")
        XCTAssertEqual(ChatComposerTextSupport.permissionModeLabel(for: "auto"), "Automatic")
        XCTAssertEqual(ChatComposerTextSupport.permissionModeLabel(for: "bypassPermissions"), "Bypass permissions")
    }

    func testWorktreeLocationLabelsUseFriendlyNames() {
        XCTAssertEqual(ChatComposerTextSupport.worktreeLocationLabel(for: false), "Work locally")
        XCTAssertEqual(ChatComposerTextSupport.worktreeLocationLabel(for: true), "New worktree")
    }

    func testSessionLocationLabelFormats() {
        XCTAssertEqual(
            ChatComposerTextSupport.sessionLocationLabel(useWorktree: false, worktreePath: nil),
            "Local"
        )
        XCTAssertEqual(
            ChatComposerTextSupport.sessionLocationLabel(
                useWorktree: false,
                worktreePath: "/tmp/worktrees/alveary/feature-abc123"
            ),
            "Local"
        )
        XCTAssertEqual(
            ChatComposerTextSupport.sessionLocationLabel(
                useWorktree: true,
                worktreePath: "/tmp/worktrees/alveary/feature-abc123"
            ),
            "Worktree (feature-abc123)"
        )
        XCTAssertEqual(
            ChatComposerTextSupport.sessionLocationLabel(useWorktree: true, worktreePath: nil),
            "Worktree"
        )
    }

    func testDeferredToolComposerStatusTextUsesRequestOverrides() {
        let askUserQuestion = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "tool-1",
            toolName: "AskUserQuestion",
            toolInput: #"{"questions":[]}"#
        )
        XCTAssertEqual(
            ChatComposerTextSupport.progressLabel(for: .toolApproval(askUserQuestion.composerStatusText)),
            "Waiting for question response..."
        )
        XCTAssertEqual(
            ChatComposerTextSupport.placeholder(for: .toolApproval(askUserQuestion.composerStatusText)),
            "Answer the pending question in the transcript..."
        )

        let bash = ToolApprovalRequest(
            sessionId: "session-1",
            toolUseId: "tool-2",
            toolName: "Bash",
            toolInput: #"{"command":"ls"}"#
        )
        XCTAssertEqual(
            ChatComposerTextSupport.progressLabel(for: .toolApproval(bash.composerStatusText)),
            "Waiting for approval..."
        )
        XCTAssertEqual(
            ChatComposerTextSupport.placeholder(for: .toolApproval(bash.composerStatusText)),
            "Waiting for tool approval..."
        )
    }

    func testFileMentionMatchesExcludePrefixFromHighlightRange() {
        let matches = ChatComposerTextSupport.fileMentionMatches(
            in: "Review (@Alveary/Views/Chat/ChatView.swift) next"
        )

        XCTAssertEqual(matches.count, 1)
        XCTAssertEqual(matches[0].highlightRange, NSRange(location: 8, length: 34))
        XCTAssertEqual(matches[0].path, "Alveary/Views/Chat/ChatView.swift")
    }

    func testTextChipDisplayModeFallsBackToFullTextWhileEditingMention() {
        let textView = AppKitTextView(frame: NSRect(x: 0, y: 0, width: 760, height: 120))
        textView.font = .preferredFont(forTextStyle: .body)
        textView.baseTextFont = .preferredFont(forTextStyle: .body)
        textView.textContainerInset = NSSize(width: 10, height: 10)
        textView.textContainer?.lineFragmentPadding = 0
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 760, height: CGFloat.greatestFiniteMagnitude)
        textView.string = "Inspect @Alveary/Views/Chat/ChatView.swift next"
        textView.updateTextContainerForCurrentBounds()
        let chip = AppTextEditorChip(
            range: NSRange(location: 8, length: 35),
            displayText: "@ChatView.swift",
            style: .fileMention
        )
        textView.textChips = [chip]
        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .compactLabel("@ChatView.swift"))
        textView.setSelectedRange(NSRange(location: 20, length: 0))
        XCTAssertEqual(textView.textChipDisplayMode(for: chip), .fullText)
    }
}
