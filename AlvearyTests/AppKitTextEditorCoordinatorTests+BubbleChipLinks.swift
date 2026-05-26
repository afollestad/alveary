import XCTest

@testable import Alveary

@MainActor
extension AppKitTextEditorCoordinatorTests {
    // File-mention chips in user bubbles are tagged with a file URL so the transcript's
    // `OpenURLAction` can reveal the file on click. Absolute paths become `file://` URLs.
    func testAppMarkdownParserTagsAbsoluteFileMentionChipWithFileURL() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatComposerTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "Check @/tmp/alveary/My%20File.txt please"
        )

        let chipLinks = attributedString.runs.compactMap { run -> URL? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return run.link
        }

        XCTAssertEqual(chipLinks.count, 1)
        XCTAssertEqual(chipLinks.first?.isFileURL, true)
        XCTAssertEqual(chipLinks.first?.path, "/tmp/alveary/My File.txt")
    }

    // Tilde-prefixed stored paths expand to absolute `file://` URLs so
    // `NSWorkspace.shared.open(_:)` can open them directly.
    func testAppMarkdownParserExpandsTildePrefixedFileMentionChip() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatComposerTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "Grab @~/Desktop/shot.png for me"
        )

        let chipLink = attributedString.runs.compactMap { run -> URL? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return run.link
        }.first

        XCTAssertEqual(chipLink?.isFileURL, true)
        XCTAssertEqual(chipLink?.path, NSHomeDirectory() + "/Desktop/shot.png")
    }

    // Relative stored paths (rebased under the thread's working directory by
    // `outboundMessage`) stay schemeless so `ChatTranscriptView.resolveMarkdownLinkURL`
    // resolves them against the thread's workingDirectory at click time.
    func testAppMarkdownParserLeavesRelativeFileMentionChipSchemeless() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatComposerTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(
            for: "Open @Alveary/Views/Chat/ChatView.swift please"
        )

        let chipLink = attributedString.runs.compactMap { run -> URL? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return run.link
        }.first

        XCTAssertNotNil(chipLink)
        XCTAssertNil(chipLink?.scheme)
        XCTAssertEqual(chipLink?.relativeString, "Alveary/Views/Chat/ChatView.swift")
    }

    // Slash-command chips are purely visual — they don't carry a click URL.
    func testAppMarkdownParserDoesNotLinkSlashCommandChips() throws {
        let parser = AppMarkdownParser(
            baseURL: nil,
            composerChipProvider: ChatComposerTextSupport.composerTextChips(in:)
        )
        let attributedString = try parser.attributedString(for: "/review-github-pr now")

        let chipLinks = attributedString.runs.compactMap { run -> URL? in
            guard let intent = run.inlinePresentationIntent, intent.contains(.code) else {
                return nil
            }
            return run.link
        }

        XCTAssertEqual(chipLinks, [])
    }
}
