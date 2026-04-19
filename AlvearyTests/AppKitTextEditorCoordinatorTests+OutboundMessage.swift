import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    // Regression guard: `highlightRange` starts at `@` and `match.range` extends back
    // to the preceding terminator char, so the replacement must re-prefix `@` — the
    // pre-encoding shape `prefix + normalizedPath` silently dropped the `@` from the
    // outbound text and from the persisted user bubble (which breaks chip re-detection).
    func testOutboundMessagePreservesAtSignForMentionInsideTerminatorChars() {
        let rewritten = ChatInputFieldTextSupport.outboundMessage(
            from: "Review (@Alveary/Views/Input/ChatInputField.swift) next",
            workingDirectory: nil
        )

        XCTAssertEqual(
            rewritten,
            "Review (@Alveary/Views/Input/ChatInputField.swift) next"
        )
    }

    // Absolute paths within the thread's working directory are rebased to relative
    // before re-encoding. Spaces must end up percent-encoded so the mention regex
    // terminates on whitespace won't chip only the leading run when the bubble
    // re-detects.
    func testOutboundMessageRebasesAbsolutePathAndEncodesSpaces() {
        let rewritten = ChatInputFieldTextSupport.outboundMessage(
            from: "Please read @/tmp/alveary/project/My%20Notes.md thanks",
            workingDirectory: "/tmp/alveary/project"
        )

        XCTAssertEqual(
            rewritten,
            "Please read @My%20Notes.md thanks"
        )
    }

    // Paths outside the working directory stay absolute after normalization — the
    // encoded form keeps spaces as `%20` so the regex doesn't terminate mid-path.
    func testOutboundMessageKeepsExternalAbsolutePathEncoded() {
        let rewritten = ChatInputFieldTextSupport.outboundMessage(
            from: "See @/tmp/other/External%20Doc.txt for context",
            workingDirectory: "/tmp/alveary/project"
        )

        XCTAssertEqual(
            rewritten,
            "See @/tmp/other/External%20Doc.txt for context"
        )
    }

    func testOutboundMessageIsIdentityWhenMessageContainsNoMentions() {
        let rewritten = ChatInputFieldTextSupport.outboundMessage(
            from: "No mentions here.",
            workingDirectory: "/tmp/alveary/project"
        )

        XCTAssertEqual(rewritten, "No mentions here.")
    }

    // Regex group 1 (`(^|[\s...])`) captures zero characters when a mention sits at the
    // start of the message, so `prefix` is `""` and the `"@"` re-prefix must still land.
    // Without the explicit `"@" +` the rewritten message would start with the raw path.
    func testOutboundMessagePreservesAtSignForMentionAtStartOfMessage() {
        let rewritten = ChatInputFieldTextSupport.outboundMessage(
            from: "@/tmp/alveary/project/Notes.md please",
            workingDirectory: "/tmp/alveary/project"
        )

        XCTAssertEqual(rewritten, "@Notes.md please")
    }

    func testOutboundMessageRewritesMultipleMentionsInOneMessage() {
        let rewritten = ChatInputFieldTextSupport.outboundMessage(
            from: "Compare @/tmp/alveary/project/A%20File.txt against @/tmp/alveary/project/B.txt please",
            workingDirectory: "/tmp/alveary/project"
        )

        XCTAssertEqual(
            rewritten,
            "Compare @A%20File.txt against @B.txt please"
        )
    }
}
